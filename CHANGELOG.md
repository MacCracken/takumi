# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_No unreleased changes._

## [0.9.5] - 2026-06-17

v7 (pre-POSIX) tar support — `extract_archive` now accepts the magic-less v7 tar
layout that real GNU release tarballs use, by gating header acceptance on the
checksum instead of the `ustar` magic. 795 tests (was 782).

### Fixed

- **`extract_archive` rejected real GNU release tarballs.** GNU hello 2.12.1 (and
  other GNU releases) ship as pre-POSIX **v7** tar — no `ustar` magic at offset
  257 — so extraction failed with `SRC_ERR_BAD_MAGIC` before verify/patch/build
  could run. Surfaced while confirming patch application (0.9.4) against a real
  project.

### Changed

- **Header validity is gated on the checksum, not the `ustar` magic**
  (`src/source.cyr`). The header checksum (offset 148) is a stronger, magic-
  independent "this is a tar header" signal and predates the magic field; it
  covers both `ustar` and v7. The initial sniff and the per-block loop now use
  `_tar_checksum_ok` and ignore the magic. v7 directories (regular typeflag with
  a trailing-slash name — v7 has no dir typeflag) are reclassified as
  directories. Security model + rationale in
  [ADR 0008](docs/adr/0008-v7-tar-checksum-gated-headers.md) (amends
  [ADR 0002](docs/adr/0002-source-extraction-safety.md)).
- Builder stamp + `takumi_version()` → 0.9.5.

### Added

- Tests: an in-memory v7 fixture builder (`_tb_finalize_v7` / `_tb_emit_file_v7`,
  checksum-valid + magic-less) — a v7 archive extracts, a pure-v7 trailing-slash
  directory is created as a directory, and a 512-byte non-tar block is still
  rejected by the checksum gate (no security regression).

### Verified

- Full pipeline confirmed live against the **real** `hello-2.12.1.tar.gz` (v7,
  magic@257 empty): fetch → verify (sha256) → extract → `patching file
  src/hello.c` → build → package — the case that failed before this release.

### Known limitations

- PAX (`x`/`g`) and GNU long-name (`L`/`K`) extended headers remain unsupported
  (`SRC_ERR_UNSUPPORTED`).

## [0.9.4] - 2026-06-17

Patch application — a recipe's `source.patches` are now applied to the extracted
source tree before the build, closing the **fetch → verify → extract → patch →
build → package** pipeline. 782 tests (was 775).

### Added

- **`apply_patches(recipe, cwd, patch_dir)`** (`src/build.cyr`) — applies each
  `source.patches` entry in order to the extracted source root by shelling out
  to the system `patch` (`patch -p1 -d <cwd> -i <file>`), `-p1` stripping the
  `a/` `b/` prefix of unified diffs. Fail-closed: returns `0 - (index+1)` of the
  first patch that fails; no patches → no-op. Patch files resolve under the
  recipes directory. Both paths are single-quoted (`_sh_squote`). Security model
  + the v7-tar follow-up in [ADR 0007](docs/adr/0007-patch-application.md).
- **Wired into `build --execute`** — `_cli_build_execute` applies patches after
  `extract_archive`, before `exec_build`; a patch failure stops the build (never
  packages un-patched source). The CLI threads the recipes `dir` as `patch_dir`.
- Tests: hermetic round-trip applies a genuine unified diff via the real `patch`
  tool and asserts the file changed, plus a non-applying patch returns non-zero.
- Integration (`scripts/integration.sh`): a loopback **fetch → verify → extract
  → patch → build → package** case with a `diff`-generated patch, asserting the
  build observed the change (needs `python3`+`tar`+`diff`).

### Verified

- Full pipeline confirmed live against **GNU hello 2.12.1** source with a real
  unified diff against `src/hello.c`: fetch → verify (sha256) → extract →
  `patching file src/hello.c` → build → package, the patched source landing in
  the fake-root.

### Changed

- Builder stamp + `takumi_version()` → 0.9.4.

### Known limitations

- Fixed `-p1` strip level; runtime dependency on `patch`.
- **v7 (pre-POSIX) tar** — surfaced while confirming against GNU hello: GNU
  release tarballs are often old v7 tar (no `ustar` magic), which
  `extract_archive` rejects (`SRC_ERR_BAD_MAGIC`) before patches run. Tracked on
  the roadmap as an extraction-layer follow-up.

## [0.9.3] - 2026-06-17

Build cwd = the extracted tarball root — the fix that makes `build --execute`
correct on real recipes. 775 tests (was 770).

### Changed

- **`exec_build` runs steps inside the extracted source root.** Tarballs
  conventionally unpack to a single top-level directory (e.g. `hello-2.12.1/`);
  `_build_cwd` now descends into it when the source dir holds exactly one
  entry and it's a directory (else uses the source dir, falling back to the
  build dir). Previously steps ran in the parent, so `./configure`/`make`
  couldn't find the source — this is what makes from-source recipes actually
  build. The cwd is computed once per build and threaded to every step.
- Builder stamp + `takumi_version()` → 0.9.3.

### Added

- Tests: `_build_cwd` (empty src → source dir; single root dir → descend;
  multiple top-level entries → source dir). The loopback integration build now
  exercises it — its recipe installs from `./README` relative to the extracted
  root.

## [0.9.2] - 2026-06-17

Source download over HTTPS — completing the `fetch → verify → extract → build
→ package` pipeline. The toolchain bump to **6.2.17 → 6.2.18** is folded into
this release. 770 tests (was 756).

### Added

- **`src/fetch.cyr` — HTTPS source download** via stdlib `sandhi` (HTTP/1.1+2,
  redirects, response cap, timeouts). `fetch_source(src, dest)` handles:
  - `url` sources → direct GET;
  - `github_release` → GET `releases/latest`, walk `assets.<i>` via dotted-path
    JSON, `_glob_match` the `release_asset` pattern, fetch the asset URL;
  - `local` → no-op (caller skips).

  Uses sandhi's **native TLS backend** (`sandhi_tls_use_native`) — no
  libssl/OpenSSL runtime dependency.
- **`build --execute` now fetches**: for non-local recipes it downloads the
  source, `verify_source_hash` against the recipe's pinned sha256 (**hard
  gate** — mismatch aborts; an unverified artifact is never extracted), then
  `extract_archive` and builds. Fail-closed throughout.
- Tests: `_glob_match` (`*`/`?`/literal/mismatch), GitHub API URL + JSON-path
  builders, `fetch_source(LOCAL)` dispatch. The integration harness drives the
  **full fetch → verify → extract → build → package** path against a loopback
  HTTP server (real download, no external dependency) — exit 0 with the `.ark`
  and installed file produced.
- [ADR 0006](docs/adr/0006-source-download.md) — source download.

### Changed

- Toolchain pin **6.2.17 → 6.2.18**; `lib/` re-vendored. `[deps] stdlib` gains
  `sandhi` + its stack (`net`/`tls`/`fdlopen`/`dynlib`/`mmap`/`async`), and
  `sync` → `thread` (one mutex provider) — which also retired the long-standing
  `thread_create`/`thread_join` baseline warnings.
- Builder stamp + `takumi_version()` → 0.9.2.
- Roadmap: source download → Completed.

### Fixed

- **Download cap**: the initial `max_response_bytes` of 512 MiB made every
  sandhi fetch fail (it pre-allocates the cap; ≳256 MiB exhausts the
  allocator). Lowered to **128 MiB**, found during live loopback bring-up.

### Notes

- Verified end-to-end over a loopback HTTP server (the harness). External-host
  fetches additionally need the environment to permit the binary's raw outbound
  TCP. Response cap is 128 MiB (in-memory); streaming large sources is future
  work.

## [0.9.1] - 2026-06-17

Build execution — the keystone. takumi can now run a recipe's `[build]` steps
into a fake-root and package the result into a `.ark`. It's also the heaviest
pre-v1 security surface, so the design leads with a deliberate invariant:
**the whole build runs unprivileged and installs only into a DESTDIR fake-root
— no root, no setuid helper** (see [ADR 0005](docs/adr/0005-build-execution.md)).
756 tests (was 733).

### Added

- **`src/build.cyr` — build executor.** `exec_build(ctx, started)` runs the six
  phases (pre_build → configure → make → check → install → post_install),
  skipping empty steps, advancing `BuildStatus`, **fail-closed** (stops on the
  first non-zero exit; never packages a partial fake-root), and returns a
  `BuildLogEntry` (COMPLETE or FAILED + phase/exit-code). Steps run via
  `/bin/sh -c` (`exec_vec`, stdout/stderr inherited) with a single-quoted env
  prelude (`PKG`/`DESTDIR` = fake-root, `CFLAGS`/`LDFLAGS` from hardening,
  `MAKEFLAGS=-j1`, `LC_ALL=C`, `umask 022`).
- **`stage_build_dirs`** — lays out `build_root/<pkg>/{src,build,pkg}` and
  empties the fake-root before a build.
- **CLI `build --execute` / `-x`** — default `build <dir>` stays a dry-run plan
  (exit 2); execute mode builds each recipe in topo order and packages
  `BS_COMPLETE` results into an unsigned `.ark`. Recipes whose source isn't
  staged (download deferred) are skipped, not failed; a failed build stops the
  run. Local meta-packages build + package trivially.
- Tests: hermetic build-execution group (trivial shell steps) — success
  populates the fake-root, a failing step is fail-closed with a phase/exit
  message, all-empty meta completes, empty middle steps skip; and a completed
  build chains `create_file_list → create_ark_manifest → ark_write → ark_read`.
  Integration harness gains a `build --execute` case that produces a real `.ark`
  for the local fixture.
- [ADR 0005](docs/adr/0005-build-execution.md) — build-execution security model.

### Changed

- Builder stamp + `takumi_version()` → 0.9.1.
- Roadmap: build execution → Completed (with the no-download caveat and the
  deferred build-sandbox noted).

## [0.9.0] - 2026-06-17

Opens the 0.9.x arc. The planned first step — integration tests + CI — was
built and immediately surfaced a real gap: takumi's CLI parsed only 434 of the
563 real zugot recipes because its source model was URL-only. So 0.9.0
**expands the recipe source model** to the three shapes zugot actually uses,
then ships the **integration harness + full CI** that validates the result.
**All 563 recipes now parse** (539 fully validate; the 24 non-validating ones
carry placeholder empty `sha256` and are correctly rejected). 733 tests
(was 712).

### Added

- **Recipe source kinds** (`src/recipe.cyr`, `src/parse.cyr`, `src/validate.cyr`):
  `SourceSpec` gains a `kind` tag —
  - `url` + `sha256` (existing),
  - `github_release = "owner/repo"` + `release_asset` + `sha256`,
  - `local = true` (meta/alias packages, no upstream source).

  New constructors `src_new_github`/`src_new_local` (legacy `src_new` unchanged
  → URL kind); parser branches by shape; validator checks per kind (URL: https
  + sha256; GitHub: `owner/repo` + asset + sha256; local: none). Resolving a
  `github_release` to an asset URL and downloading remain deferred to the
  network item; see [ADR 0004](docs/adr/0004-recipe-source-model.md).
- **Integration harness** `scripts/integration.sh` — builds the binary and
  drives the real CLI over vendored real-recipe fixtures
  (`tests/fixtures/recipes/`: a url lib, a github recipe, a local meta-package)
  asserting exit codes for `version`/`help`/`validate`/`list`/`order`/`build`,
  plus an invalid fixture (exit 1). Optionally sweeps the full zugot corpus
  when present (baseline-gated at 539/563), skipped in CI.
- **CI gates** (`.github/workflows/ci.yml`): the build job now also runs
  `fmt --check`, `lint`, the test suite, the fuzz harness, a benchmark smoke
  run, and the integration harness (was build + docs only).
- Tests: SourceSpec kind roundtrips, parser cases (github/local/missing-asset),
  validator cases (local ok, github ok, bad `owner/repo`, missing asset).
- [ADR 0004](docs/adr/0004-recipe-source-model.md) — the source model and the
  parse-vs-fetch split.

### Changed

- Builder stamp + `takumi_version()` → 0.9.0.
- Roadmap: integration tests + CI and the source-model expansion → Completed;
  corpus baseline (563 parse / 539 validate) recorded.

## [0.8.5] - 2026-06-17

`.tar.xz` and `.tar.bz2` source extraction — the codec gap from 0.8.3 is
closed now that stdlib `sankoch` 2.4.x ships xz/bzip2 (bundled in cyrius
6.2.16). 712 tests (was 700), all passing.

### Added

- **`.tar.xz` and `.tar.bz2` extraction** in `extract_archive`
  (`src/source.cyr`): magic sniff for xz (`FD 37 7A 58 5A 00`) and bzip2
  (`BZh`), decode via sankoch `decompress(FORMAT_XZ|FORMAT_BZIP2, ...)`. xz/bz2
  carry no reliable uncompressed-size header, so the output buffer grows on a
  buffer-too-small return (8× estimate, doubling, capped at 512 MiB);
  corrupt/unsupported data fails fast as `SRC_ERR_DECOMPRESS`. The gzip path
  keeps its exact ISIZE-sized decode.
- Tests: `.tar.xz` and `.tar.bz2` roundtrip (built in-test via sankoch
  `xz_compress`/`bzip2_compress` → extract → verify contents), plus a
  corrupt-xz rejection (decode fails, no crash).
- Benchmark `extract_tar_xz_10x400`: **471 µs** (xz container + LZMA2 decode +
  grow-retry + parse + write), alongside `extract_tar_gz_10x400` (438 µs).

### Changed

- Toolchain pin **6.2.14 → 6.2.16**; vendored `lib/` re-synced (brings sankoch
  2.4.3 with xz/bzip2 de/encode).
- `SrcErr.SRC_ERR_GUNZIP` renamed to **`SRC_ERR_DECOMPRESS`** (now covers
  gzip/xz/bzip2 decode failures); discriminant unchanged.
- Builder stamp + `takumi_version()` → 0.8.5.
- [ADR 0002](docs/adr/0002-source-extraction-safety.md) amended: `.tar.xz`/
  `.tar.bz2` are now supported (was a documented limitation).
- Roadmap: `.tar.xz`/`.tar.bz2` extraction moved to Completed.

## [0.8.4] - 2026-06-16

The CLI entry point — `src/main.cyr` is no longer a stub. takumi is now a
runnable tool, which unblocks the 0.9.x integration-test and CI items. 700
tests (was 680), all passing.

### Added

- **`src/cli.cyr` — command-line surface** with `cli_dispatch(args)` and a
  subcommand set:
  - `validate <recipe.cyml>...` — parse + validate each recipe; prints
    errors/warnings (exit 0 all valid, 1 any invalid/parse-fail).
  - `list <dir>` — print `name  version` per recipe, sorted.
  - `order <dir>` — print the topological build order.
  - `build <dir>` — **dry-run**: validate all, resolve order, print the plan,
    then report that execution (configure/make/install) is a 0.9.x feature
    (exit 2).
  - `version`, `help` / `-h` / `--help` / no-args usage.
- **`main.cyr`** now marshals `argv` (via `args_init`/`argc`/`argv`) into a vec
  and calls `cli_dispatch`, exiting with its return code.
- Exit-code convention (0 ok / 1 operational error / 2 usage or
  not-implemented) and the `cli_dispatch` testability split are recorded in
  [ADR 0003](docs/adr/0003-cli-surface.md).
- Tests: a `cli` group asserting exit codes via `cli_dispatch` with synthetic
  arg vecs (version/help/usage/unknown/missing-arg) and `cmd_*` against `.cyml`
  fixtures (valid→0, malformed→1, missing dir→1, list/order/build over a
  2-recipe chain).

### Changed

- `src/main.cyr` no longer prints `"takumi ready"`; it dispatches the CLI.
- Builder stamp → `takumi/0.8.4`; new `takumi_version()` in `src/cli.cyr` joins
  the version-sync set (`VERSION` / `cyrius.cyml` / builder stamp).
- Roadmap: `main.cyr` CLI entry point moved to Completed; integration tests +
  CI noted as unblocked.

## [0.8.3] - 2026-06-16

Source integrity & file fidelity — more 0.9.x I/O work pulled into the 0.8.x
arc to settle the input/extraction security surface before the pre-v1 audit.
680 tests (was 603), all passing; benches green.

### Added

- **Symlink classification in the fake-root walk** (`src/package.cyr`): the
  walker now `lstat`s every entry first, so a symlink is recorded as
  `ARK_FT_SYMLINK` with its `readlink` target and is **never followed** —
  `is_dir` (which resolves links) only runs on non-links. Closes the prior
  bite's gap where a symlinked directory was walked at its target (cycle risk),
  and makes `.ark` archives record links faithfully.
- **`.tar` / `.tar.gz` extractor** (`src/source.cyr`):
  `extract_archive(archive_path, dest_dir)` — gzip sniff + ISIZE-sized gunzip
  (stdlib `sankoch`), ustar parse with header-checksum validation, and a
  **fail-closed path-traversal guard** (rejects `..`, absolute paths,
  NUL/control/backslash, and symlink targets that escape the destination;
  unsupported typeflags abort rather than risk mis-extraction). 512 MiB cap.
  Format/guard model in [ADR 0002](docs/adr/0002-source-extraction-safety.md).
  `.tar.xz`/`.tar.bz2` are rejected — no xz/bzip2 codec in the stdlib yet.
- **Source-hash verification** (`src/source.cyr`):
  `verify_source_hash(path, expected_sha256)` — streamed SHA-256 compared to
  the recipe's `source.sha256`, to run before extraction.
- Tests: symlink classification (symlinked dir not recursed), extractor
  pure-helper units, positive extraction (regular/dir/symlink, empty file,
  multi-block file, prefix+name, `.tar.gz`, 10×400 archive, empty archive), and
  the malicious set (`../escape`, `a/../b`, `/etc/x`, absolute/escaping symlink
  targets, unsupported typeflag, bad checksum, truncated, bad magic) — each
  asserting the specific `SRC_ERR_*` and that no out-of-root artifact is
  written.
- Benchmarks: `extract_tar_gz_10x400` **449 µs** (gunzip + parse + guard +
  write for a 10-file archive) and `verify_source_hash_64k` **205 µs**.
- [ADR 0002](docs/adr/0002-source-extraction-safety.md) — source extraction
  safety.

### Changed

- Toolchain pin **6.2.12 → 6.2.14**; vendored `lib/` re-synced from the 6.2.14
  snapshot (`cyrius lib sync`), clearing the pin-drift warning.
- Builder stamp → `takumi/0.8.3`.
- Roadmap: symlink classification, `.tar`/`.tar.gz` extraction, and source
  verification moved to Completed; remaining 0.9.x I/O (network download,
  build execution, patch application, `.tar.xz`/`.tar.bz2`) re-scoped with the
  xz/bz2 codec gap noted.

## [0.8.2] - 2026-06-16

The `.ark` on-disk package format — pulled from the 0.9.x roadmap into the
0.8.x arc to settle artifact integrity before the pre-v1 security audit.
takumi can now serialize a built package to a reproducible, compressed,
signed `.ark` file (and read one back to verify it). 603 tests (was 543),
all passing.

### Added

- **`.ark` v1 writer + reader** (`src/ark_format.cyr`):
  `ark_write(manifest, entries, fake_root, out_path, signing_seed)` and
  `ark_read(path, max_len)`. Format: little-endian header (magic + version
  + flags), TOML-text manifest, uncompressed file index, DEFLATE data
  section, SHA-256 root hash, trailing ed25519 signature. Specified in
  [ADR 0001](docs/adr/0001-ark-binary-format.md).
- **Manifest embedded as TOML**, parsed back via stdlib `bayan`. Symmetric,
  self-contained escaping (`\`, `"`, newline, tab, CR) — takumi escapes on
  write and un-escapes on read (bayan delimits but does not un-escape).
- **Data-section compression** via stdlib `sankoch` DEFLATE at a pinned
  level (6), recorded in the header and asserted on read. Manifest + index
  stay uncompressed so a reader gets metadata without inflating payloads.
- **Package signing** via sigil 3.8.0 ed25519: the SHA-256 root hash is
  signed with a deterministic key; the public key is embedded and verified
  on read.
- **Integrity verification on read**: `ark_read` recomputes the root hash,
  verifies the signature, and re-checks every per-file SHA-256; any
  mismatch returns failure.
- Tests: signed/unsigned roundtrip, byte-for-byte reproducibility
  (same inputs built twice → identical bytes), tamper detection, empty
  package, and symlink/directory entries.
- Benchmark `ark_write_26_files_signed`: **2.71 ms** for the 26-file
  fixture (read payloads + DEFLATE + SHA-256 root + ed25519 sign + write),
  measured alongside `create_file_list_26_files` (422 µs) and `sha256_1mb`
  (3.13 ms).
- `docs/adr/` tree established, starting with ADR 0001 (`.ark` format).

### Changed

- `[deps] stdlib` gains `sankoch` (DEFLATE) and `sync` (its mutex
  dependency). Both vendored from the 6.2.12 snapshot.
- Builder stamp → `takumi/0.8.2`; `main` documented; reproducibility now
  depends on the pinned `sankoch`/`sigil` versions (`cyrius.lock`).
- Roadmap: `.ark` archive creation and package signing moved to Completed;
  backlog re-labelled 0.9.x; v1.0 criterion #7 updated from the Rust-era
  `cargo clippy`/`cargo audit` wording to the Cyrius gates + security audit.

## [0.8.1] - 2026-06-16

Toolchain and dependency refresh. No source-level behavior change —
all 543 tests pass and benchmarks hold at parity (`parse_full_recipe`
36 µs, `resolve_build_order_300` 444 µs, `create_file_list_26_files`
412 µs, `sha256_1mb` 3.81 ms on this host). The headline change is the
CYML/TOML/bigint parser migration: the Cyrius standard library absorbed
takumi's recipe-parsing primitives into `bayan`, so the locally
vendored copies are retired in favor of the upstream module.

### Changed

- **Toolchain**: pinned Cyrius bumped **5.5.23 → 6.2.12** (`cyrius.cyml`).
- **CYML/TOML parsing now comes from stdlib `bayan`**: `cyml_parse`,
  `cyml_doc_header`/`cyml_doc_header_len`, `toml_parse`, `toml_get`,
  `toml_section_name`/`toml_section_pairs` (and the 256-bit integer
  helpers they relied on) are now provided by `lib/bayan.cyr`. The
  function names and arities are unchanged, so `src/parse.cyr` is
  untouched. This matches ark and nous, which already consume `bayan`.
- **Vendored stdlib refreshed to the 6.2.12 snapshot** (`lib/*.cyr`).
  The 6.x stdlib split slice subscripting into `lib/slice.cyr`, which
  `agnosys` now requires; `slice` is added to the `[deps] stdlib` list
  ahead of the modules that pull `agnosys`.
- **`sigil` dependency 2.9.0 → 3.8.0** (`cyrius.cyml [deps.sigil]`).
  `lib/sigil.cyr` remains a symlink to the sibling `../sigil/dist`
  bundle, which is at 3.8.0.
- **Builder stamp**: `ArkManifest.builder` is now `takumi/0.8.1`
  (`src/package.cyr`).

### Added

- `[deps] stdlib` gains `slice`, `process`, `bayan`, `random`, and
  `thread_local` — required by the refreshed `agnosys`/`sigil` bundles
  and the `bayan` parser. Vendored into `lib/` from the 6.2.12 snapshot.

### Removed

- `lib/cyml.cyr`, `lib/toml.cyr`, and `lib/bigint.cyr` — superseded by
  the stdlib `bayan` module. Their `cyml`/`toml`/`bigint` entries are
  dropped from the `[deps] stdlib` list.

## [0.8.0] - 2026-04-21

Full rewrite from Rust to Cyrius. Version jumped from the pre-release
0.1.0 scaffold directly to 0.8.0 to synchronize with
[ark](https://github.com/MacCracken/ark) 0.8.0 and align cadence across
the AGNOS package-manager stack. This release reaches **in-memory
parity with the 0.1.0 Rust scaffold** — every type, pure function, and
benchmark has a Cyrius counterpart (see [benchmarks-rust-v-cyrius.md](benchmarks-rust-v-cyrius.md)
for measured numbers). I/O (download / extract / build / archive /
sign) and the CLI entry point remain in the 0.9.x roadmap.

543 tests, 0 failures, 11 benchmarks at parity with the Rust scaffold.
Nine source files, ~1100 lines of Cyrius.

### Breaking

- **Language**: implementation switched from Rust to Cyrius (toolchain
  pinned to 5.5.23). Consumers no longer depend on takumi as a Rust
  crate; integration is via Cyrius `include "src/<module>.cyr"` under a
  project pulling the 5.5.23+ toolchain and the `sigil` 2.9.0 dep.
- **Recipe format**: TOML → CYML (TOML header above `---`, markdown
  body below, parsed zero-copy via `lib/cyml.cyr`). `.toml` recipe
  files in [zugot](https://github.com/MacCracken/zugot) will be renamed
  to `.cyml` alongside this release. A single recipe file now carries
  both the structured fields and the maintainer prose (build notes,
  upgrade guidance) that previously lived in a sibling doc.
- **Public API**: Rust `Vec<String>` / `HashMap<String, _>` /
  `Result<_, _>` signatures replaced with Cyrius `vec_*` / `map_*` /
  tagged-`Result` (`lib/tagged.cyr`). Every recipe string value is a
  cstring; enum discriminants are fixed integer values stable across
  versions (do not renumber).
- **Name validation**: narrowed from Rust's `char::is_alphanumeric`
  (Unicode) to ASCII-only. The Rust impl would have admitted Cyrillic
  `а` as distinct from Latin `a`, enabling homoglyph collisions; the
  port rejects non-ASCII package and dependency names outright.
- **`validate_recipe` semantics**: accumulates every error and every
  warning in a single pass (`ValidateResult { errors, warnings }`)
  rather than short-circuiting via `bail!` at the first fatal. Within
  one entity (a name, a version, a given dep) we still stop at the
  first issue to avoid duplicate messages.
- **`ArkManifest` construction**: zero-init + chained setters
  (`man_alloc()` + `man_set_*`) instead of a single 13-arg
  constructor. Cyrius 5.5.23's direct `fn` declarations corrupt middle
  arg positions past a 9-arg threshold; the setter pattern matches
  ark's vendored sigil `trust_policy` convention.
- **Builder stamp**: `ArkManifest.builder` now records
  `"takumi/0.8.0"`. Pre-0.8 manifests stamp `"takumi/0.1.0"`; consumers
  that diff builder strings should accept both.

### Added

- `src/types.cyr` — `HardeningFlag`, `ArkFileType`, `BuildStatus`
  enums. Stable integer discriminants, canonical lowercase name
  conversions, `hf_from_cstr` accepting Rust-style snake/kebab-case
  aliases (`full_relro`, `full-relro`, `stack_protector`, …).
  Payload-carrying Rust variants (`Symlink(String)`, `Failed(String)`)
  become tag-only; the payload lives on the owning struct.
- `src/validate.cyr` — nine ASCII-only predicates (`byte_is_digit`,
  `byte_is_alpha`, `byte_is_lower_hex`, `byte_is_allowed_name_char`,
  `name_contains_unsafe`, `name_has_only_allowed_chars`,
  `url_has_valid_scheme`, `sha256_is_lowercase_hex64`,
  `version_has_multiple_parts`) plus the `validate_recipe(recipe) →
  ValidateResult` orchestrator.
- `src/topo.cyr` — Kahn's topological sort with deterministic
  lex-ascending tiebreaker. `resolve_build_order(packages, adj_map)`
  returns `Ok(vec)` or `Err(TOPO_ERR_CYCLE)`; `cycle_members(packages,
  order)` recovers the cycle participants after a failed resolve.
  Local helpers `cstr_cmp`, `vec_insert_sorted_cstr`, `vec_reverse`,
  `cstr_vec_contains` kept inline pending a second consumer.
- `src/flags.cyr` — CFLAGS / LDFLAGS assembly from `HardeningFlag`
  vecs. Rust's insertion-order + compiler/linker-only filtering +
  FullRelro-dedup rules preserved exactly (dedup holds in every
  ordering). `cstr_join_spaces` mirrors Rust's `Vec::join(" ")`.
- `src/recipe.cyr` — parsed-recipe layout: `PackageMetadata`,
  `SourceSpec`, `DependencySpec`, `BuildSteps`, `SecurityFlags`, plus
  the aggregate `BuildRecipe`. Offset-enum + `alloc` + `load64`/
  `store64` convention matching the rest of the Cyrius stdlib (only
  `Str` in the entire stdlib uses the `struct` keyword).
- `src/parse.cyr` — CYML recipe parser. `recipe_parse_str(data, len)`
  and `recipe_parse_file(path)` return a `BuildRecipe` pointer or `0`
  on failure. All values copied out of the parse buffer as fresh
  cstring allocations so callers may discard the input buffer after
  parsing. `_cyml_header_normalize` promotes `[section]` →
  `[[section]]` at line starts so `lib/toml.cyr`'s vidya-shaped
  (arrays-of-tables only) parser can process plain-table recipes
  without touching bracketed content inside string values.
- `src/ark.cyr` — layout for `.ark` output: `ArkManifest` (13 fields),
  `ArkFileEntry` (5 fields — the Rust `ArkFileType::Symlink(String)`
  inline payload becomes a neighbor `symlink_target` field), and
  `ArkPackage` (the outer container: manifest, signature, files,
  data_hash — signature is a hex Ed25519 string so the struct stays
  in cstring-land). Convenience constructors `afe_regular`,
  `afe_directory`, `afe_symlink`, `afe_config`.
- `src/engine.cyr` — remaining non-layout items from the Rust scaffold.
  - `BuildContext` (recipe + source_dir + build_dir + package_dir +
    output_dir + arch) — runtime directory layout for one package build.
  - `BuildLogEntry` (package + status + started_at + completed_at +
    duration_secs + fail_msg) — timestamped log line. `completed_at`
    and `duration_secs` are `0` when None; `fail_msg` carries the
    payload-promoted message for `BS_FAILED` entries.
  - `TakumiBuildSystem` — the stateful engine container owning
    `loaded_recipes` (cstr-keyed map of `BuildRecipe`) and `build_log`
    (vec of `BuildLogEntry`).
  - `tbs_load_all_recipes(sys)` — recursively scans the engine's
    `recipes_dir` for `.cyml` files and populates the recipe map.
    Non-`.cyml` files and unparseable recipes are silently skipped,
    matching the Rust `warn!` + continue behavior.
- `src/package.cyr` — fake-root walker + SHA-256 hasher + manifest
  composer:
  - `_hash_and_size(path)` reads each file once in 4 KiB chunks
    (matching sigil's `hash_file` stride), returning `{hex, size}`
    so no second `stat` syscall is needed.
  - `_walk` recurses via `lib/fs.cyr` `dir_list` + `is_dir`; emits an
    entry for every directory and every regular file.
  - `_ark_type_for(rel)` classifies `/etc/*` as `ARK_FT_CONFIG`.
  - `_afe_sort` insertion-sorts by path via `cstr_cmp` for
    deterministic manifest output.
  - `create_file_list(package_dir)` + `sum_installed_size(entries)`.
  - `create_ark_manifest(recipe, entries, default_arch_cstr,
    build_date_secs)` composes a fully populated `ArkManifest`;
    `build_date_secs` is a parameter (not an internal
    `clock_epoch_secs()` call) so tests stay deterministic.
- 543-assertion test suite in `tests/takumi.tcyr`. Includes two
  real-filesystem integration tests: the walker test builds a tree
  under `/tmp/takumi-b6b-test/` with `sys_mkdir` + `file_write_all`,
  walks it, checks ordering, file-type classification, sizes, and
  verifies every walker hash against a direct `sigil::sha256_hex`
  call on the same bytes; the engine test writes two `.cyml` files
  plus a non-`.cyml` junk file to `/tmp/takumi-engine-test/`,
  scans via `tbs_load_all_recipes`, and confirms only the `.cyml`
  files register.
- `tests/takumi.bcyr` — 11 benchmarks mirroring `rust-old/benches/
  takumi_bench.rs`. See [benchmarks-rust-v-cyrius.md](benchmarks-rust-v-cyrius.md) for the full
  parity table; the Rust `manifest_json_roundtrip` bench is
  dropped (no serde in the port — equivalent path is the
  `man_alloc` + setter sequence, O(13) and covered by
  `validate_recipe` timings).

### Performance (measured vs. rust-old baseline)

All runs on the same x86_64 Linux host. Full table in
[benchmarks-rust-v-cyrius.md](benchmarks-rust-v-cyrius.md). Summary:

| Benchmark                       | Rust   | Cyrius  | Cyrius / Rust |
|---------------------------------|--------|---------|---------------|
| `parse_full_recipe`             | 16.7 µs |   29 µs | 1.74×         |
| `resolve_build_order_300`       |  134 µs |  540 µs | 4.03×         |
| `create_file_list_26_files`     |  219 µs |  481 µs | 2.20×         |
| `sha256_1mb`                    |  516 µs | 67.26 ms | **130×**     |

- The 2–4× ratios on parse / topo / file-walk reflect an unoptimized
  first port and are acceptable for the takumi workload (tens of
  recipes, hundreds of files per recipe — absolute times stay in the
  single-digit milliseconds).
- **SHA-256 is ~130× slower.** `lib/sigil.cyr` ships a portable
  Cyrius SHA-256; Rust's `sha2` crate uses hand-vectorized
  assembly with SHA-NI / AVX2 intrinsics. Closing this gap is an
  upstream-sigil item, not a takumi concern.
- `scripts/bench-history.sh` rewritten for Cyrius: builds
  `tests/takumi.bcyr`, runs it, and appends a per-bench CSV row to
  `bench-history.csv` for tracking across commits.

### Changed

- `VERSION` bumped from `0.1.0` to `0.8.0`. Mirrored in
  `cyrius.cyml` and in the `ArkManifest.builder` stamp in
  `src/package.cyr`.
- Documentation rewritten for the CYML format and the Cyrius
  implementation: `README.md` example now shows a full `.cyml` with
  TOML header + markdown body; `docs/architecture/overview.md`
  documents the `.cyml → cyml_parse → toml_parse → BuildRecipe`
  pipeline; `CLAUDE.md` cleanliness commands swapped from
  `cargo fmt/clippy/audit/deny/doc` to
  `cyrius fmt/lint/vet/deny/doc`, and the "key principles" section
  now references Cyrius invariants (stable enum discriminants,
  `alloc_init()` discipline, no aborts from library code) rather
  than `#[non_exhaustive]` / `#[must_use]` / serde.

### Infrastructure

- `cyrius.cyml` toolchain pinned to released tag **5.5.23** (never a
  dev version — matches the ecosystem-wide rule in the migration
  strategy).
- Stdlib `[deps]` list: `string fmt alloc vec str syscalls io args
  assert hashmap tagged cyml toml fs freelist bigint ct keccak chrono`
  — every transitive dep sigil needs.
- `[deps.sigil]` pinned to **2.9.0** (matches cyrius 5.5.23's own
  sigil pin) with `path = "../sigil"` local-checkout hint.
- `.github/workflows/ci.yml` and `release.yml` scaffolded by
  `cyrius port`. End-to-end CI validation deferred until the CLI
  entry point lands in 0.9.x.

### Fixed (vs. Rust scaffold latent issues)

- Unicode-aware name validation could admit homoglyph collisions
  (Cyrillic `а` vs Latin `a`). The port's ASCII-only check rejects
  these.
- Rust `validate_recipe` forced recipe authors to re-run validation
  after each fix; the port surfaces every error and every warning
  at once.

## [0.1.0] - Unreleased (superseded by 0.8.0)

Initial Rust scaffold. Never tagged; frozen in `rust-old/` as the
authoritative reference until the Cyrius port reaches full feature
parity.

### Added

- Core recipe types: `BuildRecipe`, `PackageMetadata`, `SourceSpec`,
  `DependencySpec`, `BuildSteps`, `SecurityFlags`, `HardeningFlag`.
- `.ark` output types: `ArkPackage`, `ArkManifest`, `ArkFileEntry`,
  `ArkFileType`.
- Build context and status: `BuildContext`, `BuildStatus`,
  `BuildLogEntry`.
- `TakumiBuildSystem` engine with single + recursive recipe loading,
  validation, topological sort, CFLAGS/LDFLAGS generation, `.ark`
  manifest creation, and symlink-safe directory walking.
- `#[non_exhaustive]` on all public enums; `#[must_use]` on all pure
  functions; serde `Serialize`/`Deserialize` on every public type.
- 74 unit tests including serde roundtrip tests.
- Criterion benchmark suite (12 benchmarks) with `bench-history.sh`.

### Performance (Rust baseline, archived for future comparison)

- `resolve_build_order_300`: 134 µs (HashSet optimization: −49% vs
  naive `Vec::contains` — 300-package chain 265 → 134 µs).
- `parse_full_recipe`: 16.7 µs.
- `create_file_list_26_files`: 219 µs (lookup-table byte-to-hex
  encoding for `hex_sha256` contributed −11%).
- `sha256_1mb`: 516 µs.
