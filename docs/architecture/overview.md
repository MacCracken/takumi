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
5. Package:  installed files -> ArkManifest + ArkFileEntry list -> .ark
```

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
| `cyml` + `toml` | Recipe file parsing — `cyml` splits header/body, `toml` parses the header |
| `tracing` | Structured logging |
