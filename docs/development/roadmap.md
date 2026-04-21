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
      [BENCHMARKS.md](../../BENCHMARKS.md)
- [x] `#[non_exhaustive]` on all public enums
- [x] `#[must_use]` on all pure functions
- [x] Serde roundtrip tests for all types (74 tests)
- [x] Criterion benchmark suite (12 benchmarks)
- [x] P(-1) scaffold hardening pass

## Backlog (0.1.x)

- [ ] Source download with SHA-256 verification
- [ ] Source extraction (tar.gz, tar.xz, tar.bz2)
- [ ] Patch application
- [ ] Build execution (shell-out to configure/make/install)
- [ ] Fake-root installation directory management
- [ ] `.ark` package archive creation (actual file format)
- [ ] Package signing infrastructure
- [ ] `main.cyr` CLI entry point (replaces Rust's `main.rs`)
- [ ] Integration tests with real recipe files
- [ ] CI pipeline (GitHub Actions) — scaffolded by `cyrius port`, to
      be validated end-to-end once the CLI lands
- [ ] Symlink classification in `create_file_list` — `lstat` +
      `readlink` + explicit `ARK_FT_SYMLINK` emission. `is_dir` from
      `lib/fs.cyr` follows links today, so a symlinked directory is
      walked at its target (cycle-risk exists but is rare for real
      fake-roots)

## Future (0.2+)

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
7. Zero `cargo clippy` warnings, zero `cargo audit` advisories
8. Benchmark suite covers all hot paths
