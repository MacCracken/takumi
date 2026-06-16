# Architecture Overview

## System Context

Takumi is the build engine in the AGNOS ecosystem. It reads CYML recipes
(TOML header + markdown body in one file) from the
[zugot](https://github.com/MacCracken/zugot) repository and produces
`.ark` packages for installation by `ark`.

```
zugot (recipes)  -->  takumi (build engine)  -->  .ark packages  -->  ark (installer)
```

## Module Map

Takumi is currently a single-module library (`src/lib.rs`) with the following
logical sections:

### Recipe Types (Input)

| Type | Purpose |
|------|---------|
| `BuildRecipe` | Complete recipe parsed from a `.cyml` file (header only; body is prose documentation) |
| `PackageMetadata` | Package identity: name, version, description, license, groups, release, arch |
| `SourceSpec` | Source tarball URL, SHA-256 hash, patch list |
| `DependencySpec` | Runtime and build-time dependency lists |
| `BuildSteps` | Shell commands: configure, make, check, install, pre_build, post_install |
| `SecurityFlags` | Hardening configuration: flag list + custom CFLAGS/LDFLAGS |
| `HardeningFlag` | Enum: Pie, Relro, FullRelro, Fortify, StackProtector, Bindnow |

### Package Types (Output)

| Type | Purpose |
|------|---------|
| `ArkPackage` | Complete built package: manifest, signature, file entries, data hash |
| `ArkManifest` | Package metadata embedded in the `.ark` file |
| `ArkFileEntry` | Single file: path, SHA-256, size, type |
| `ArkFileType` | Enum: Regular, Directory, Symlink(target), Config |

### Build System

| Type | Purpose |
|------|---------|
| `TakumiBuildSystem` | Main engine: loads recipes, validates, resolves order, produces manifests |
| `BuildContext` | Runtime context for a single package build |
| `BuildStatus` | Build state machine: Pending through Complete/Failed |
| `BuildLogEntry` | Timestamped log entry for build auditing |

## Data Flow

```
1. Load:     .cyml files -> CymlDoc (cyml_parse) -> TOML header (toml_parse) -> BuildRecipe structs
2. Validate: BuildRecipe -> Result<warnings> (reject malformed early)
3. Resolve:  [package names] -> topological build order (Kahn's algorithm)
4. Build:    (not yet implemented) download, extract, configure, make, install
5. Package:  installed files -> ArkManifest + ArkFileEntry list (src/package.cyr)
             -> serialized .ark v1 (src/ark_format.cyr): TOML manifest +
                file index + DEFLATE data + SHA-256 root + ed25519 signature
```

### `.ark` serialization (`src/ark_format.cyr`)

`ark_write(manifest, entries, fake_root, out_path, signing_seed)` produces a
reproducible, signed `.ark` v1 file; `ark_read(path, max_len)` reads and fully
verifies one (root hash, signature, every per-file hash) and is the conformance
harness until ark grows its own reader. The on-disk format — a little-endian
header, TOML-text manifest (parsed back via `bayan`), uncompressed file index,
DEFLATE-compressed data section (stdlib `sankoch`, pinned level), SHA-256 root
hash, and trailing ed25519 signature (sigil) — is specified in
[ADR 0001](../adr/0001-ark-binary-format.md).

## Key Algorithms

### Build Order Resolution

Uses Kahn's algorithm for topological sort with O(1) dependency lookup via
`HashSet`. Detects cycles and reports involved packages. Produces deterministic
output via sorted queue.

### Security Flag Generation

Converts `HardeningFlag` enum values to GCC-compatible CFLAGS and LDFLAGS
strings. Handles deduplication: `FullRelro` implies both `-z,relro` and
`-z,now`, so explicit `Relro` and `Bindnow` flags are skipped when
`FullRelro` is present.

## Dependencies

| Crate | Purpose |
|-------|---------|
| `anyhow` | Error handling with context |
| `chrono` | Build timestamps |
| `serde` + `serde_json` | Serialization for all types |
| `sha2` | SHA-256 integrity hashing |
| `bayan` (stdlib) | Recipe file parsing — `cyml_parse` splits header/body, `toml_parse` parses the header (absorbed into stdlib `bayan` as of 0.8.1; formerly vendored `lib/cyml.cyr` + `lib/toml.cyr`) |
| `tracing` | Structured logging |
