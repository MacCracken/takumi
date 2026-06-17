# 0010 — Streaming source download (lift the 128 MiB cap)

- **Status**: accepted (takumi 0.9.7)
- **Date**: 2026-06-17
- **Builds on**: [ADR 0006](0006-source-download.md) (source download via sandhi)

## Context

Source download (0.9.2, ADR 0006) used sandhi's **buffered** client
(`sandhi_http_get_opts`), which pre-allocates the whole response body up front
via `max_response_bytes`. Values ≳256 MiB exhaust the bump allocator, so takumi
capped source artifacts at **128 MiB** in memory — and the whole body sat
resident during the fetch. That excluded large sources (toolchains, kernels,
browser engines) and wasted memory on every fetch.

The gap was a missing sandhi capability — a download-to-fd / body-sink that
streams the body without buffering it. takumi filed the request as the first
consumer (ADR 0006 follow-up, sandhi roadmap). It shipped in **sandhi 1.6.5
(Cyrius 6.2.19)** as `sandhi_http_download(url, fd, opts)` /
`sandhi_http_download_sink(url, cb, ctx, opts)`.

## Decision

Bump the toolchain pin to **6.2.19** (re-vendoring `lib/`, sandhi → 1.6.5) and
switch the **artifact** download from the buffered client to the streaming one.

`src/fetch.cyr` — `_sandhi_download_to_file(url, dest)` (replaces
`_sandhi_get_to_file`):
- opens `dest` (`O_WRONLY|O_CREAT|O_TRUNC`, 0644) and calls
  `sandhi_http_download(url, fd, opts)`, whose built-in fd-sink flushes each
  decoded chunk straight to the file — the body is never held whole in memory;
- honors redirect-follow (GitHub release → CDN), TLS policy, and a 10-minute
  `total_ms` wall clock; **no byte cap** (the streaming path deliberately
  ignores `max_response_bytes` — see sandhi's `download.cyr` note);
- maps the 32-byte download result: a non-2xx final status or a transport
  `err_kind` → `FETCH_ERR_HTTP`; a destination-write failure (the fd sink
  returning `<0`, surfaced as `SANDHI_ERR_INTERNAL`) → `FETCH_ERR_WRITE`.

The small **GitHub release JSON** is still fetched buffered (`FETCH_MAX_JSON`,
4 MiB) — it's tiny and needs `sandhi_json_*` over an in-memory body. Only the
artifact streams.

The verify-before-use contract is unchanged: the streamed file is sha256-checked
against the recipe's pinned hash before extraction (ADR 0006's hard gate).

## Consequences

- **Source size is no longer capped in memory** — bounded only by free disk and
  the `total_ms` wall clock. The resident set during a fetch is fixed (sandhi's
  256 KiB working buffers) regardless of artifact size.
- **Verified live**: a 180 MiB source (188,753,920 bytes — well over the old
  134,217,728 cap) fetched → sha256-verified (exact match) → extracted → built →
  packaged end-to-end over a loopback server; the buffered path would have
  failed at this size. The existing loopback fetch + patch + PAX integration
  cases now exercise the streaming path (it's the only artifact-download path).
- **No new size backstop in CI** — proving "no in-memory cap" is a memory
  property, not an output; the 180 MiB confirmation is recorded here rather than
  baked into CI as a slow large-artifact fixture. A consumer that wants a hard
  size ceiling can bound it via `total_ms` (today) or a custom sink (future).
- `FETCH_MAX_BYTES` is removed (the artifact path no longer has an in-memory
  cap); `FETCH_TOTAL_MS` (600 s) is now the download backstop.
- Runtime: still native TLS, **no libssl/OpenSSL dependency**.

## Alternatives considered

- **Raise `max_response_bytes` to a few hundred MiB** — rejected; it
  pre-allocates that much per fetch and still OOMs the bump allocator past
  ~256 MiB. A cap is not a fix.
- **Custom byte-sink (`sandhi_http_download_sink`) instead of the fd helper** —
  unnecessary; the destination is a plain file, and the built-in fd sink already
  loops over partial writes. Revisit if takumi needs to tee/hash-on-the-fly.
- **Hash while streaming (skip the second read)** — a nice future optimization
  (feed the sink into both the file and a sha256 state), but it couples fetch and
  verify; kept separate for now. Noted as a follow-up.

## Follow-ups

- Optionally hash-on-the-fly in the sink to avoid re-reading the file for
  `verify_source_hash`.
- A configurable max-size sink if a deployment wants a hard disk-use ceiling
  below the timeout backstop.
