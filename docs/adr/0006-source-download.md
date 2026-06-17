# 0006 — Source download (HTTPS via sandhi)

- **Status**: accepted (takumi 0.9.2)
- **Date**: 2026-06-17

## Context

`build --execute` (0.9.1) could build `local` recipes but skipped every `url`/
`github_release` recipe because takumi couldn't fetch. 0.9.2 adds fetching so
the full pipeline — **fetch → verify → extract → build → package** — runs over
real recipes.

The stdlib's `http.cyr` is a plaintext-only client (no TLS, 64 KB cap, no
redirects) — unusable for https sources. The right tool is **`sandhi`**
(v1.6.3), the stdlib HTTP/1.1+2 client with redirect-following, response caps,
timeouts, and dotted-path JSON. (My first pass wrongly concluded a TLS client
had to be built; it already exists. Lesson: survey the stdlib's higher-level
modules, not just the obviously-named one.)

## Decision

`src/fetch.cyr` — `fetch_source(src, dest)` dispatches on `src_kind`:
- **URL**: `sandhi_http_get_opts` (follow_redirects, max_response_bytes 128 MiB,
  total timeout) → write body to `dest`.
- **GITHUB**: GET `api.github.com/repos/<repo>/releases/latest` (with a
  `User-Agent`), walk `assets.<i>.name` via `sandhi_json_get_string`,
  `_glob_match` the recipe's `release_asset` pattern, fetch the matching
  `browser_download_url`.
- **LOCAL**: returns a distinct no-source code; the caller skips fetching.

**TLS backend = native.** `fetch_source` calls `sandhi_tls_use_native()` — the
pure-Cyrius TLS stack — instead of the deprecated libssl/fdlopen bridge (which
carries a documented brk/fdlopen crash note). Consequence: **no libssl/OpenSSL
runtime dependency.**

**Verify-before-use.** The CLI `build --execute` path fetches to a scratch
file, then `verify_source_hash(file, recipe.sha256)` is a **hard gate** — a
mismatch aborts the build; an unverified artifact is never extracted. Then
`extract_archive` into the source dir, then `exec_build`. Fail-closed
throughout. `url` sources are https-only (validator-enforced).

## Consequences

- `build --execute` now does a real fetch for non-local recipes (it no longer
  "skips, source pending"). The in-process unit tests stay hermetic (glob, kind
  dispatch, URL/JSON-path builders, `fetch_source(LOCAL)`), and the integration
  harness drives the **full fetch → verify → extract → build → package** path
  against a **loopback HTTP server** (`scripts/integration.sh`, needs
  `python3`+`tar`) — a real download, no external dependency.
- **Verified end to end.** The loopback harness build fetches a tarball, the
  sha256 gate passes, it extracts, runs the install step, and produces a `.ark`.
  External-host fetches additionally require the environment to permit the
  binary's raw outbound TCP (in the dev agent sandbox, non-loopback connects are
  blackholed and `curl` only works via a proxy; that's an environment policy,
  not a takumi/sandhi issue).
- **Response cap = 128 MiB.** sandhi pre-allocates `max_response_bytes`; values
  ≳256 MiB exhaust the allocator and the request fails (found during live
  bring-up — an initial 512 MiB cap broke every fetch). 128 MiB covers
  effectively all source tarballs; oversized sources are a documented limit.
- Body is buffered in memory (bounded by the 128 MiB cap), consistent with the
  extractor.

## Known limitations / follow-ups

- **Response cap 128 MiB** (sandhi in-memory pre-alloc); streaming-to-disk for
  very large sources is future work.
- **Tarball root dir**: extraction lands the archive's top-level dir under the
  source dir; build cwd is the source dir. Recipes whose steps assume cwd =
  extracted-root may need a "single top-level dir → cwd" refinement (follow-up).
- GitHub resolution uses `releases/latest` only (no tag pinning yet); `*`/`?`
  globs over asset names.
- No mirror/fallback URLs, no resume, no checksum-TOFU.

## Alternatives considered

- **Build a TLS HTTP client on `tls.cyr`** — unnecessary; sandhi already is one.
- **Shell out to `curl`/`wget`** — avoided; sandhi keeps it in-process with no
  external-binary dependency (build execution shells out, but fetching doesn't
  need to).
- **libssl backend** — rejected as the default (deprecated, fdlopen crash note,
  adds an OpenSSL runtime dep); native backend is used instead.
