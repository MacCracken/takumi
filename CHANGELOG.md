# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **Language**: ported from Rust to Cyrius (toolchain pinned to 5.5.23). Rust
  scaffold preserved under `rust-old/` as the authoritative reference until
  the port reaches feature parity.
- **Recipe format**: switched from plain TOML to [CYML](https://github.com/MacCracken/cyrius/blob/main/lib/cyml.cyr)
  (TOML header above `---`, markdown body below, parsed zero-copy). One
  file now holds both the structured recipe metadata and the prose build
  notes / upgrade guidance that used to live in separate docs. `.toml`
  recipes in zugot will be renamed to `.cyml` as the port progresses.
  Header parse still goes through `lib/toml.cyr`; CYML just gives the
  body a first-class home.

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
- `src/flags.cyr` — GCC CFLAGS/LDFLAGS assembly from a
  `HardeningFlag` vec plus an optional extra cstring. Rust behavior
  preserved exactly: insertion order kept, linker-only flags skipped
  from CFLAGS, compiler-only flags skipped from LDFLAGS. `FullRelro`
  deduplication drops redundant `Relro` and `Bindnow` whenever
  `FullRelro` is present, regardless of ordering. Shared
  `cstr_join_spaces` utility mirrors `Vec::join(" ")`.
- 31 new CFLAGS/LDFLAGS tests (per-flag, linker/compiler filtering,
  multi-flag ordering, FullRelro dedup in every position, extra
  appending). Total suite: **235 assertions, 0 failures**.
- `src/recipe.cyr` — in-memory model for the parsed recipe. Five sub-
  structs (`PackageMetadata`, `SourceSpec`, `DependencySpec`, `BuildSteps`,
  `SecurityFlags`) plus the aggregate `BuildRecipe`. Offset-enum + alloc +
  load64/store64 layout, matching cyrius's own `struct`-avoiding
  convention (only `Str` in the entire stdlib uses `struct` syntax).
  `_new` constructors and `_field` accessors per type. Strings are
  cstrings throughout; `0` is `None` on the optional fields (`arch`,
  `cflags`, `ldflags`, all `BuildSteps`). The parse boundary will
  convert `Str` values out of `lib/toml.cyr` into cstrings before
  populating these structs.
- 53 new recipe-model tests (per-sub-struct roundtrip, optional-None
  handling, full recipe composition, pointer-identity through the
  aggregate, two-recipe independence). Total suite: **288 assertions,
  0 failures**.
- `src/parse.cyr` — CYML recipe parser. `recipe_parse_str(data, len)`
  and `recipe_parse_file(path)` return a `BuildRecipe` pointer or `0`
  on failure (missing required section/field, unknown hardening flag
  — matches Rust's strict serde behavior). All values are copied out
  of the parse buffer as fresh cstring allocations so callers can
  discard the input buffer once parsing completes.
- `_cyml_header_normalize` — preprocessor that promotes `[section]`
  → `[[section]]` at line starts. `lib/toml.cyr` is vidya-centric and
  only recognizes `[[section]]` (arrays-of-tables); without this shim
  every pair in a recipe landed in one unnamed section. The promoter
  only touches line-leading `[`, so bracketed content inside string
  values is safe.
- `[deps] stdlib` in `cyrius.cyml` extended with `cyml`, `toml`, `fs`.
- 58 new parse tests (minimal/full roundtrip, CYML-with-body parses
  header only, missing required sections/fields → 0, unknown
  hardening flag → 0, alias parsing works, array edge cases).
  Total suite: **346 assertions, 0 failures**.
- `validate_recipe` orchestrator in `src/validate.cyr` — composes the
  bite-#2 predicates over a parsed `BuildRecipe`. Returns a
  `ValidateResult` with separate `errors` and `warnings` vecs; the
  caller treats empty errors as Ok. Deliberate departure from Rust:
  the Rust impl short-circuits at the first fatal via `bail!`; this
  port accumulates *all* errors and *all* warnings in one pass so a
  recipe author sees every problem at once. Within a single entity
  (the name, the version, a given dep) we still stop at the first
  hit to avoid duplicate messages for the same underlying issue.
- Error-emitting rules (fatal): empty `package.name`, unsafe or
  disallowed chars in name, empty `package.version`, empty
  `source.url`, non-http(s) scheme, empty `source.sha256`, empty /
  unsafe / disallowed chars in any dep name.
- Warning-emitting rules (advisory): single-component version,
  empty description, empty license, `release == 0`, malformed
  SHA-256 (length or hex), no build steps at all, no hardening.
- 49 new validator tests (clean recipe, every error path, every
  warning path, build-step silencing rules, multi-issue accumulation,
  `val_ok` accessor semantics). Total suite: **395 assertions, 0
  failures**.

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
