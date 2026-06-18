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

- [x] Real-package builds (0.10.1) — extraction now preserves file **mode**
      (`+x` on `./configure`) and **mtime** (no spurious autotools regen), and
      the build prelude bakes a standard **PATH** (so `gcc` finds `cc1`). These
      were the blockers to compiling real packages; found + fixed by building
      GNU hello end to end (configure → make → install → `.ark`, sandboxed,
      produces a working binary). [ADR 0013](../adr/0013-real-package-builds.md).

- [x] GNU long-name/long-link tar headers (`L` = 76, `K` = 75) (0.10.2) — the
      entry's data block carries the next entry's long name/linkname (pre-PAX
      mechanism). Same intercept-and-override path as PAX, through the same
      traversal guard. Completes the tar matrix (ustar + v7 + PAX + GNU). Model
      in [ADR 0009](../adr/0009-pax-extended-headers.md). Verified byte-identical
      to system `tar` on a real `--format=gnu` long-path archive.

## Backlog (0.9.x)
- [x] Build sandbox — network isolation + timeout (0.9.8) — `src/sandbox.cyr`
      `exec_vec_sandboxed` runs each build step in a fresh **network namespace**
      (unprivileged user-namespace + identity uid/gid map; hermetic, no external
      net) and under a **wall-clock timeout** (process-group `SIGKILL` on
      overrun). Best-effort isolation (CLI probes + reports the mode). Model in
      [ADR 0011](../adr/0011-build-sandbox.md). Verified live (build saw only
      `lo`; correct file ownership; overrun killed). First installment of
      ADR 0005's deferred sandbox.
- [x] Build sandbox — filesystem confinement (Landlock) (0.10.0) —
      `src/sandbox.cyr` confines a build step's writes to the build/temp area
      (`/` read+exec, `/tmp` + `/dev` read-write) via Landlock, hand-rolled on
      the `sys_landlock_*` stdlib wrappers (no agnosys dep). Best-effort + probed
      (`sandbox_fs_available`). Model in
      [ADR 0012](../adr/0012-landlock-fs-confinement.md). Verified live (a write
      outside the build area is blocked; `$PKG` writes succeed).
- [ ] Build sandbox — seccomp syscall filtering + `--require-sandbox`
      (fail-closed) + PID/mount namespaces + per-recipe timeout override +
      tighter per-build write area. **Audit-informed**: the 0.11.x security audit
      decides which are v1-warranted (likely seccomp + `--require-sandbox`) vs
      post-1.0. See the [Path to 1.0](#path-to-10-the-011x-arc) and
      [ADR 0011](../adr/0011-build-sandbox.md) / [0012](../adr/0012-landlock-fs-confinement.md).

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

## Path to 1.0 (the 0.11.x arc)

The remaining work, sequenced. The last feature lands *before* the audit so the
audit reviews the complete v1 surface; remediation + audit-warranted sandbox
extras follow; then the 1.0 tag. (Decisions: criterion 1 met via driver +
runbook; sandbox extras are audit-informed.)

- [x] **0.11.0 — Base-system build driver + operator runbook** (closes
  criterion 1). **Done.**
  - `build --execute --keep-going` (`-k`): build every recipe in topo order,
    continue past a failed package, skip a failed package's dependents, and print
    a `built / failed / skipped` summary (per-package lines name the failing
    phase). Default stays fail-closed; exit 1 if anything failed.
  - `docs/guides/base-system-build.md`: operator runbook (toolchain prereqs,
    `SOURCE_DATE_EPOCH`, sandbox modes, reading the report).
  - Criterion 1 → met (demonstrated end-to-end real build + driver + runbook; a
    full 309-package compile is an operator/CI activity).

- [x] **0.11.1 — Pre-v1 security audit** (review only). **Done.**
  `docs/compliance/security-audit-2026.md`: threat-model-driven per-stage review
  + external comparison + residual-risk + remediation plan. **22 findings (2
  critical, 3 high, 6 medium, 6 low, 5 info)**, each verified against the code.
  Closes criterion 7's audit half. The critical/high set drives 0.11.2–0.11.5.

- [x] **0.11.2 — Input hardening** (audit cluster). **Done.** PAX
  `size=`/record-length overflow guards + overflow-safe write bound (SEC-01
  CRITICAL, SEC-03 HIGH), https-only + loopback `http` carve-out (SEC-06),
  malformed-sha → error (SEC-07), GitHub URL re-validate (SEC-12), streaming
  size cap via counting sink (SEC-13), `SRC_MAX_BYTES` = allocator ceiling +
  null-checked allocs (SEC-14). Regression tests added; 859 tests green.
- [x] **0.11.3 — Sandbox hardening** (audit cluster). **Done.** userns
  map-failure aborts the step (SEC-04 HIGH), sandbox-setup failures warn +
  `--require-sandbox` fail-closed (SEC-08), Landlock confines to the build root
  not all `/tmp` + `TMPDIR` redirect (SEC-09), arch-correct `ppoll` sleep on
  aarch64 (SEC-10), `/dev` narrowed to existing nodes (SEC-15); SEC-11 (double-
  fork timeout escape) documented as a trusted-recipe residual (PID ns
  deferred). Sandbox policy refactored to an `SbCfg` struct. 868 tests; verified
  live. seccomp deferred post-1.0.
- [x] **0.11.4 — `.ark` reader robustness** (audit cluster). **Done.** Every
  length/offset/count in `ark_read` is bounds-checked against the verified
  content region before use (`_ark_in`), `u_len` capped at `ARK_MAX_DATA`, allocs
  null-checked (SEC-05 HIGH); manifest ints clamped non-negative (SEC-16). 871
  tests; malformed-`.ark` regression test added.
- [x] **0.11.5 — Package signing / key management** (audit cluster). **Done.**
  `--signing-key <path>` (64-hex ed25519 seed) threaded into `ark_write`;
  fail-closed on a bad key, loud UNSIGNED warning when absent (SEC-02 CRITICAL).
  Signed `.ark`s verify on read. [ADR 0014](../adr/0014-package-signing-key.md).
  **All audit findings now remediated — the 0.11.x security arc is complete.**

- **1.0.0 — v1 release**: all eight criteria ✅, audit findings resolved or
  risk-accepted, final docs/CHANGELOG/version pass, tag 1.0.0.

## v1.0 Criteria

Status: ✅ met · ◐ partial · ☐ open.

1. ✅ Can build the full AGNOS base system from zugot recipes — the pipeline
   **builds real packages end to end** (GNU hello: configure → make → install →
   `.ark`, sandboxed; 0.10.1, [ADR 0013](../adr/0013-real-package-builds.md)),
   and `build --execute --keep-going` + the
   [base-system runbook](../guides/base-system-build.md) drive a whole recipe set
   with a built/failed/skipped report (0.11.0). The complete 309-package compile
   is an operator/CI activity (every build dep + machine-hours).
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
7. ✅ Clean `cyrius audit` (fmt + lint 0 warnings + vet + deny) and a completed
   pre-v1 security audit — audit done (0.11.1,
   [security-audit-2026.md](../compliance/security-audit-2026.md): 22 findings)
   and **fully remediated** across 0.11.2–0.11.5 (SEC-11 a documented residual).
8. ✅ Benchmark suite covers all hot paths (extract gz/xz/bz2, sha256,
   ark_write, flags).
