# Development Roadmap

## Completed

- [x] Core recipe types with serde support
- [x] Recipe parsing from TOML files (single and recursive directory scan) — Rust only; being replaced with CYML (TOML header + markdown body) in the Cyrius port
- [x] Recipe validation: name safety, URL scheme, SHA-256 format, dependency
      name validation (Cyrius port accumulates all errors+warnings in one pass)
- [x] Build order resolution via topological sort (Kahn's algorithm)
- [x] Security hardening flag generation (CFLAGS/LDFLAGS)
- [x] `.ark` manifest creation with file list and SHA-256 hashes
- [x] Symlink-safe directory traversal (Rust scaffold; Cyrius port
      currently walks without explicit symlink handling — TODO below)
- [x] Full type parity with the Rust scaffold (`ArkPackage`,
      `BuildContext`, `BuildLogEntry`, `TakumiBuildSystem`) — added in
      the 0.8.0 parity pass
- [x] Recursive `.cyml` directory scan via `tbs_load_all_recipes`
- [x] Benchmark parity — 11 of 12 Rust benches ported
      (`manifest_json_roundtrip` dropped; no serde in Cyrius). See
      [benchmarks-rust-v-cyrius.md](../../benchmarks-rust-v-cyrius.md)
- [x] `#[non_exhaustive]` on all public enums
- [x] `#[must_use]` on all pure functions
- [x] Serde roundtrip tests for all types (74 tests)
- [x] Criterion benchmark suite (12 benchmarks)
- [x] P(-1) scaffold hardening pass
- [x] `.ark` package archive creation (on-disk v1 format) — reproducible,
      DEFLATE-compressed (stdlib `sankoch`), SHA-256 root hash, ed25519
      signing (sigil). Writer + reader in `src/ark_format.cyr`; format
      spec in [ADR 0001](../adr/0001-ark-binary-format.md). Pulled into
      the 0.8.x arc (0.8.2) to settle artifact integrity before the
      pre-v1 security audit.
- [x] Package signing infrastructure — ed25519 over the `.ark` root
      hash, deterministic (reproducible) keys, embedded pubkey, verified
      on read.
- [x] Symlink classification in `create_file_list` (0.8.3) — `lstat`-first
      so symlinks are emitted as `ARK_FT_SYMLINK` with their `readlink`
      target and never followed; symlinked directories are no longer walked
      at their target (cycle risk closed).
- [x] Source extraction `.tar` / `.tar.gz` / `.tar.xz` / `.tar.bz2`
      (0.8.3 gz; 0.8.5 xz/bz2) — `extract_archive` in `src/source.cyr`:
      magic sniff + decode via stdlib `sankoch` (gzip ISIZE-sized; xz/bz2
      grow-retry), ustar parse, and a fail-closed path-traversal guard.
      Format/guard model in
      [ADR 0002](../adr/0002-source-extraction-safety.md).
- [x] Source SHA-256 verification (0.8.3) — `verify_source_hash` checks a
      staged tarball against the recipe's `source.sha256` before extraction.
- [x] `main.cyr` CLI entry point (0.8.4) — `src/cli.cyr` `cli_dispatch` with
      `validate` / `list` / `order` / `build` (dry-run plan) / `version` /
      `help`; exit-code convention + testability split in
      [ADR 0003](../adr/0003-cli-surface.md). Unblocks integration tests + CI.
- [x] Recipe source model — url / `github_release` / `local` kinds (0.9.0).
      Parser + validator branch by kind; see
      [ADR 0004](../adr/0004-recipe-source-model.md). takumi now parses 100%
      of the zugot corpus (563/563); 539 fully validate (24 carry placeholder
      empty `sha256` and are correctly rejected).
- [x] Integration tests + CI (0.9.0) — `scripts/integration.sh` drives the
      real CLI over vendored recipe fixtures (`tests/fixtures/recipes/`) +
      optional zugot corpus sweep; `ci.yml` now runs fmt/lint/test/fuzz/bench/
      integration gates.
- [x] Build execution + fake-root staging (0.9.1) — `src/build.cyr`
      `exec_build` runs the `[build]` steps via `/bin/sh -c` into a DESTDIR
      fake-root, fail-closed, then packages to `.ark`; CLI `build --execute`.
      **Unprivileged + DESTDIR-only** (no root/shakti); security model in
      [ADR 0005](../adr/0005-build-execution.md). Full coverage over real
      recipes waits on source download.

- [x] Source download over HTTPS (0.9.2) — `src/fetch.cyr` `fetch_source` via
      stdlib `sandhi` (native TLS, no libssl dep): `url` + `github_release`
      (API + JSON + glob) kinds; wired into `build --execute` with a
      verify-before-extract hard gate. Security model in
      [ADR 0006](../adr/0006-source-download.md). Verified end-to-end over a
      loopback HTTP server (full fetch → verify → extract → build → package);
      128 MiB response cap.

- [x] Build cwd = extracted tarball root (0.9.3) — `_build_cwd` descends into
      the archive's single top-level dir so `./configure`/`make` run in the
      source root; makes `build --execute` correct on real recipes.

- [x] Patch application (0.9.4) — `apply_patches` (`src/build.cyr`) applies a
      recipe's `source.patches` to the extracted source root after extract,
      before build, by shelling out to the system `patch` (`-p1`); fail-closed,
      wired into `build --execute`. Security model in
      [ADR 0007](../adr/0007-patch-application.md). Pipeline is now **fetch →
      verify → extract → patch → build → package**. Confirmed live against GNU
      hello 2.12.1 source with a real unified diff.

- [x] v7 (pre-POSIX) tar extraction (0.9.5) — `extract_archive` now gates header
      acceptance on the **checksum** (`_tar_checksum_ok`), not the `ustar` magic,
      so it accepts the magic-less v7 layout real GNU release tarballs use (GNU
      hello 2.12.1 failed with `SRC_ERR_BAD_MAGIC` before). v7 dirs (regular
      typeflag + trailing-slash name) are reclassified as directories. No
      security regression (checksum is a stronger gate than the magic). Model in
      [ADR 0008](../adr/0008-v7-tar-checksum-gated-headers.md). Confirmed live
      against the real v7 GNU hello tarball.

- [x] PAX extended header support (0.9.6) — `extract_archive` parses
      POSIX.1-2001 PAX headers (`x` per-file, `g` global) for
      `path`/`linkpath`/`size` overrides, so modern long-path tarballs extract
      (OpenSSL 3.3.0 / CPython 3.12.3 failed with `SRC_ERR_UNSUPPORTED` before).
      Overrides flow through the existing path-traversal guards (no new
      surface). Model in [ADR 0009](../adr/0009-pax-extended-headers.md).
      Verified byte-identical to system `tar` on real OpenSSL/CPython tarballs.
      (GNU `L`/`K` long-name headers deferred — not seen in any sampled tarball.)

- [x] Streaming source download (0.9.7) — the artifact streams straight to disk
      via sandhi's `sandhi_http_download(url, fd, opts)` (shipped in sandhi 1.6.5
      / Cyrius 6.2.19; takumi was the first consumer ask from 0.9.2). Source size
      is no longer capped at 128 MiB in memory — bounded only by disk + the
      total-ms wall clock, with a fixed resident set. Model in
      [ADR 0010](../adr/0010-streaming-download.md). Verified live with a 180 MiB
      source (over the old cap).

## Backlog (0.9.x)
- [ ] GNU long-name/long-link tar headers (`L` = 76, `K` = 75) — the entry's
      data block carries the next entry's long name/linkname (not PAX records).
      Deferred from 0.9.6: appeared in none of the sampled real tarballs (PAX is
      the modern mechanism); add on the first real instance. See
      [ADR 0009](../adr/0009-pax-extended-headers.md).
- [x] Build sandbox — network isolation + timeout (0.9.8) — `src/sandbox.cyr`
      `exec_vec_sandboxed` runs each build step in a fresh **network namespace**
      (unprivileged user-namespace + identity uid/gid map; hermetic, no external
      net) and under a **wall-clock timeout** (process-group `SIGKILL` on
      overrun). Best-effort isolation (CLI probes + reports the mode). Model in
      [ADR 0011](../adr/0011-build-sandbox.md). Verified live (build saw only
      `lo`; correct file ownership; overrun killed). First installment of
      ADR 0005's deferred sandbox.
- [ ] Build sandbox — filesystem confinement (Landlock) — confine a step's
      writes to DESTDIR + the build dir (read-only elsewhere). stdlib `agnosys`
      `security_apply_landlock` (RO/RW fs rules) is the intended primitive; pulls
      agnosys as a dep. Next sandbox bite.
- [ ] Build sandbox — seccomp syscall filtering + PID/mount namespaces +
      per-recipe timeout override + optional `--require-sandbox` (fail-closed).
      Later sandbox bites. See [ADR 0011](../adr/0011-build-sandbox.md).

- [x] ark-side `.ark` reader / installer — **implemented in ark**
      (`ark/src/ark_package.cyr`): verifies root hash + ed25519 signature,
      parses the manifest + file index, inflates the DEFLATE data, and
      re-verifies every per-file content hash; format matches takumi's writer
      field-for-field. Conformance ref `src/ark_format.cyr` +
      [ADR 0001](../adr/0001-ark-binary-format.md).

## Future (post-0.9.x)

- [ ] Parallel builds for independent packages
- [ ] Build caching / ccache integration
- [ ] Cross-compilation support
- [ ] `noarch` package support (scripts, docs, fonts)
- [ ] Epoch field for version comparison
- [ ] `provides` / `conflicts` / `replaces` fields
- [ ] Multiple source URLs per recipe
- [ ] Explicit `backup` file list (beyond `/etc/` heuristic)
- [ ] Build options / feature flags per recipe
- [ ] `size_compressed` in manifest

## v1.0 Criteria

Status: ✅ met · ◐ partial · ☐ open.

1. ◐ Can build the full AGNOS base system from zugot recipes — the per-package
   pipeline is complete + hardened; a full multi-package base-system build run
   is still to be done.
2. ✅ Reproducible builds: same recipe + same sources = identical `.ark` output
   — deterministic writer + `SOURCE_DATE_EPOCH` (0.9.9); proven byte-identical
   in the integration harness.
3. ✅ All packages have SHA-256 checksums (manifest + per-file + root hash).
4. ✅ All packages are signed (ed25519; ark re-verifies on read).
5. ✅ Build order handles the full 309-package dependency graph — Kahn's
   algorithm; covered by a 312-node hermetic test + a full-corpus `order` sweep
   (535 packages) in integration (0.9.9).
6. ✅ Documentation complete: architecture, guides, examples, ADRs — guides +
   examples landed in 0.9.9 (11 ADRs, architecture overview, roadmap).
7. ◐ Clean `cyrius audit` (fmt + lint 0 warnings + vet + deny) ✅ and a
   completed pre-v1 security audit ☐ (the capstone; Landlock fs confinement
   (0.10.0) lands first to harden the recipe-shell surface).
8. ✅ Benchmark suite covers all hot paths (extract gz/xz/bz2, sha256,
   ark_write, flags).
