# Takumi

**Takumi** (Japanese: 匠 — master craftsman) — Package build system for AGNOS.

The craftsman that reads [zugot](https://github.com/MacCracken/zugot) recipes and produces `.ark` packages. Given a CYML recipe defining source, dependencies, build steps, and security flags, takumi downloads, builds, hardens, and packages the result.

## What Takumi Does

Takumi is the build engine. It reads recipe files, resolves build order, executes build steps with security hardening flags, and outputs signed `.ark` packages ready for installation by [ark](https://github.com/MacCracken/ark).

```
zugot recipe (.cyml) → takumi → .ark package
                         ├── download source (verify SHA256)
                         ├── configure (with hardening flags)
                         ├── build (make / cargo / cyrius)
                         ├── check (tests)
                         ├── install (to staging dir)
                         ├── generate manifest + file list
                         └── package as .ark
```

## Recipe Format — CYML

Recipes are `.cyml` files in the [zugot](https://github.com/MacCracken/zugot) repository. CYML is [Cyrius's](https://github.com/MacCracken/cyrius) own format: a TOML header above `---`, markdown below. The header carries the structured fields takumi needs; the body is a place for maintainer notes, upgrade guidance, and build quirks — in the same file as the recipe rather than a separate doc.

```cyml
[package]
name = "hoosh"
version = "1.2.0"
description = "Hoosh — AI inference gateway"
license = "GPL-3.0-only"
groups = ["tool", "ai", "rust"]
release = 1
arch = "x86_64"

[source]
url = "https://github.com/MacCracken/hoosh/archive/refs/tags/1.2.0.tar.gz"
sha256 = "abc123..."

[depends]
runtime = ["glibc", "openssl"]
build = ["rust", "openssl-dev"]

[build]
make = "cargo build --release"
check = "cargo test"
install = """
mkdir -p $PKG/usr/bin
cp target/release/hoosh $PKG/usr/bin/
"""

[security]
hardening = ["pie", "fullrelro", "fortify", "stackprotector", "bindnow"]

---

# Hoosh

AI inference gateway. Packaged from upstream releases.

## Build notes

- Requires Rust 1.80+; pulls openssl-dev at build time for the TLS backend.
- On first upgrade past 1.2.0, clear `/var/lib/hoosh/cache` — the cache
  format is not backward compatible with pre-1.2 runtimes.
```

## Core Types

| Type | Description |
|------|-------------|
| `TakumiBuildSystem` | Main engine — loads recipes, resolves build order, executes builds |
| `BuildRecipe` | Parsed CYML recipe header (package metadata, source, deps, build steps, security) |
| `PackageMetadata` | Name, version, description, license, groups, arch |
| `SourceSpec` | Source URL, release asset pattern, SHA256 hash |
| `DependencySpec` | Runtime and build dependencies |
| `BuildSteps` | Configure, make, check, install, pre/post scripts |
| `SecurityFlags` | Hardening flags (PIE, RELRO, FORTIFY, stack protector, BIND_NOW) |
| `ArkPackage` | Built package ready for distribution |
| `ArkManifest` | Package manifest with file list, hashes, metadata |
| `ArkFileEntry` | Individual file in a package (path, hash, type, permissions, size) |
| `BuildContext` | Build environment (directories, environment variables, status) |

## Security Hardening

Every package built by takumi is compiled with security hardening flags:

| Flag | CFLAGS/LDFLAGS | Effect |
|------|----------------|--------|
| `pie` | `-fPIE -pie` | Position-Independent Executable (ASLR) |
| `fullrelro` | `-Wl,-z,relro,-z,now` | Full RELRO (GOT protection) |
| `fortify` | `-D_FORTIFY_SOURCE=2` | Buffer overflow detection |
| `stackprotector` | `-fstack-protector-strong` | Stack smashing protection |
| `bindnow` | `-Wl,-z,now` | Immediate symbol binding |
| `stackclash` | `-fstack-clash-protection` | Stack clash protection |
| `cfprotection` | `-fcf-protection` | Control flow integrity |

Takumi generates the appropriate CFLAGS and LDFLAGS from the recipe's `[security]` section. No package ships without hardening.

## API

```rust
use takumi::TakumiBuildSystem;

let mut build = TakumiBuildSystem::new(
    recipes_dir,   // path to zugot recipes
    build_root,    // scratch build directory
    output_dir,    // where .ark packages go
);

// Load all recipes from zugot
let count = build.load_all_recipes()?;

// Validate a recipe
let warnings = TakumiBuildSystem::validate_recipe(&recipe)?;

// Resolve build order (topological sort by dependencies)
let order = build.resolve_build_order(&["hoosh", "daimon"])?;

// Generate hardening flags
let cflags = TakumiBuildSystem::generate_cflags(&recipe.security);
let ldflags = TakumiBuildSystem::generate_ldflags(&recipe.security);

// Create .ark manifest
let manifest = TakumiBuildSystem::create_ark_manifest(&recipe, &package_dir)?;
```

## Build Order

Takumi resolves build order via dependency-aware topological sort. For the base system, zugot provides `build-order.txt` — a pre-computed 309-package build sequence (base + desktop) that respects all dependency chains.

## Dependencies

| Crate | Purpose |
|-------|---------|
| anyhow | Error handling |
| serde / serde_json | Serialization |
| cyml + toml | Recipe parsing (cyml splits header/body; toml parses the header) |
| sha2 | Integrity verification |
| tracing | Structured logging |
| chrono | Timestamps |

## Related

- [ark](https://github.com/MacCracken/ark) — Package manager CLI (installs what takumi builds)
- [nous](https://github.com/MacCracken/nous) — Package resolver (resolves dependencies)
- [zugot](https://github.com/MacCracken/zugot) — Recipe repository (the recipes takumi reads)
- [sigil](https://github.com/MacCracken/sigil) — Trust verification (signs built packages)
- [AGNOS Philosophy](https://github.com/MacCracken/agnosticos/blob/main/docs/philosophy.md)

## License

GPL-3.0-only
