# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_No unreleased changes._

## [0.8.0] - 2026-04-21

Full rewrite from Rust to Cyrius. Version jumped from the pre-release
0.1.0 scaffold directly to 0.8.0 to synchronize with
[ark](https://github.com/MacCracken/ark) 0.8.0 and align cadence across
the AGNOS package-manager stack. This release reaches **in-memory
parity with the 0.1.0 Rust scaffold** — every type, pure function, and
benchmark has a Cyrius counterpart (see [BENCHMARKS.md](BENCHMARKS.md)
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
  takumi_bench.rs`. See [BENCHMARKS.md](BENCHMARKS.md) for the full
  parity table; the Rust `manifest_json_roundtrip` bench is
  dropped (no serde in the port — equivalent path is the
  `man_alloc` + setter sequence, O(13) and covered by
  `validate_recipe` timings).

### Performance (measured vs. rust-old baseline)

All runs on the same x86_64 Linux host. Full table in
[BENCHMARKS.md](BENCHMARKS.md). Summary:

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
