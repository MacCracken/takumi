# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **Language**: ported from Rust to Cyrius (toolchain pinned to 5.5.23). Rust
  scaffold preserved under `rust-old/` as the authoritative reference until
  the port reaches feature parity.

### Added (Cyrius port)

- `src/types.cyr` — `HardeningFlag`, `ArkFileType`, `BuildStatus` enums with
  stable integer discriminants and canonical lowercase name conversions.
  `hf_from_cstr` accepts the same snake/kebab-case aliases as the Rust
  `FromStr` impl (`full_relro`, `full-relro`, `stack_protector`, …).
  Variants with Rust payloads (`Symlink(String)`, `Failed(String)`) are
  tag-only; the payload will live on the owning struct.
- 64 tests in `tests/takumi.tcyr` covering discriminants, canonical names,
  aliases, unknown-input rejection, and name roundtrip.
- `src/validate.cyr` — pure validation predicates split out of the Rust
  `TakumiBuildSystem::validate_recipe` monolith: `byte_is_digit`,
  `byte_is_alpha`, `byte_is_lower_hex`, `byte_is_allowed_name_char`,
  `name_contains_unsafe`, `name_has_only_allowed_chars`,
  `url_has_valid_scheme`, `sha256_is_lowercase_hex64`,
  `version_has_multiple_parts`. ASCII-only by design (the Rust impl used
  `char::is_alphanumeric`, which admitted Unicode homoglyphs and would
  have allowed collision-prone package names).
- 71 validation predicate tests. Total suite: **135 assertions, 0 failures**.
- `src/topo.cyr` — dependency-order resolution via Kahn's topological
  sort: `resolve_build_order(packages, adj_map) -> Ok(vec) | Err(TOPO_ERR_CYCLE)`.
  Ties are broken by ascending lexicographic name so the build order is
  deterministic across runs. Dependencies outside the input set are
  ignored (caller pre-filters). `cycle_members(packages, order)` recovers
  the cycle participants after a failed resolve. Local helpers
  (`cstr_cmp`, `vec_insert_sorted_cstr`, `vec_reverse`, `cstr_vec_contains`)
  kept inline pending a second consumer.
- `cyrius.cyml` stdlib now includes `hashmap` and `tagged` — required
  for the topo sort and the `Ok`/`Err` tagged-Result API. Without these
  in the auto-include list, calls to `map_new`/`Ok`/`Err` silently
  linked to garbage at runtime and produced an infinite print loop.
- 69 new topological-sort tests (helpers, empty/single/chain/fan-out/
  diamond/external-dep/self-loop/mutual/3-cycle/partial-cycle/
  determinism/cycle_members). Total suite: **204 assertions, 0 failures**.

### Rust scaffold (prior to port, now frozen in `rust-old/`)

- Core build recipe types: `BuildRecipe`, `PackageMetadata`, `SourceSpec`,
  `DependencySpec`, `BuildSteps`, `SecurityFlags`, `HardeningFlag`
- `.ark` package output types: `ArkPackage`, `ArkManifest`, `ArkFileEntry`,
  `ArkFileType`
- Build context and status types: `BuildContext`, `BuildStatus`, `BuildLogEntry`
- `TakumiBuildSystem` engine with:
  - Single and recursive recipe loading from TOML files
  - Recipe validation with path traversal protection, URL scheme enforcement,
    SHA-256 format checking, and dependency name validation
  - Topological sort build order resolution (Kahn's algorithm) with cycle
    detection
  - Security flag generation: CFLAGS/LDFLAGS with FullRelro deduplication
  - `.ark` manifest creation with SHA-256 file hashing
  - Directory walking with symlink-safe traversal
- `#[non_exhaustive]` on all public enums for forward compatibility
- `#[must_use]` on all pure functions
- Serde `Serialize`/`Deserialize` on every public type
- 74 unit tests including serde roundtrip tests for all types
- Criterion benchmark suite (12 benchmarks) with `bench-history.sh` for
  tracking
- Baseline benchmark numbers:
  - `resolve_build_order_300`: 134 us (HashSet optimization: -49% vs naive)
  - `parse_full_recipe`: 16.7 us
  - `create_file_list_26_files`: 219 us
  - `sha256_1mb`: 516 us

### Performance

- `resolve_build_order`: replaced O(n) `Vec::contains` with O(1)
  `HashSet::contains` for dependency filtering. 300-package chain: 265 us ->
  134 us (-49%)
- `hex_sha256`: replaced per-byte `format!("{:02x}")` with lookup table.
  Contributed to -11% improvement in `create_file_list`

## [0.1.0] - Unreleased

Initial scaffold release. Core types, validation, build ordering, and file
listing. No actual package building yet (download, extract, compile, package
phases are not implemented).
