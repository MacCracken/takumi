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

## Backlog (0.9.x)

- [ ] Source download (network fetch over HTTPS) — incl. resolving
      `github_release` → asset URL; pairs with `verify_source_hash`
- [ ] Patch application
- [ ] Build execution (shell-out to configure/make/install)
- [ ] Fake-root installation directory management
- [ ] ark-side `.ark` reader / installer (consumes the 0.8.2 format) —
      tracked on ark's roadmap (ark `docs/development/roadmap.md`, "`.ark`
      package format" backlog); conformance ref is `src/ark_format.cyr`
      + [ADR 0001](../adr/0001-ark-binary-format.md)

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

1. Can build the full AGNOS base system from zugot recipes
2. Reproducible builds: same recipe + same sources = identical `.ark` output
3. All packages have SHA-256 checksums
4. All packages are signed
5. Build order handles the full 309-package dependency graph
6. Documentation complete: architecture, guides, examples, ADRs
7. Clean `cyrius audit` (fmt + lint 0 warnings + vet + deny) and a
   completed pre-v1 security audit
8. Benchmark suite covers all hot paths
