# Takumi

**Takumi** (Japanese: 匠 — master craftsman) — Package build system for AGNOS.

The craftsman that reads [zugot](https://github.com/MacCracken/zugot) recipes and produces `.ark` packages. Given a CYML recipe defining source, dependencies, build steps, and security flags, takumi downloads, builds, hardens, and packages the result.

## What Takumi Does

Takumi is the build engine. It reads recipe files, resolves build order, runs
the build in a sandbox with security hardening, and outputs signed, reproducible
`.ark` packages ready for installation by [ark](https://github.com/MacCracken/ark).

```
zugot recipe (.cyml) → takumi build --execute → .ark package
   ├── parse + validate      (strict: safe names, https, sha256 shape)
   ├── fetch                 (HTTPS, native TLS, streamed to disk)
   ├── verify                (SHA-256 hard gate — never extract unverified)
   ├── extract               (tar ustar/v7/PAX/GNU · gz/xz/bz2 · traversal-guarded)
   ├── patch                 (source.patches via `patch -p1`)
   ├── build (sandboxed)     (net namespace + Landlock fs confinement + timeout,
   │                          unprivileged, into a DESTDIR fake-root)
   └── package               (manifest + per-file SHA-256, DEFLATE, ed25519-signed)
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

## Using takumi (CLI)

takumi is a single binary. Build it with `cyrius build src/main.cyr build/takumi`.

| Command | What it does |
|---------|--------------|
| `takumi validate <recipe.cyml>...` | Parse + validate recipes (errors + warnings) |
| `takumi list <dir>` | List recipes in a directory |
| `takumi order <dir>` | Print the topological build order |
| `takumi build <dir>` | Print the build plan (dry run; exit 2) |
| `takumi build <dir> --execute` | Run the full pipeline into a fake-root and write `.ark`s |
| `takumi version` / `help` | Version / usage |

Flags for `build --execute` (`-x`):

- **`--keep-going` (`-k`)** — build every package, skip a failed package's
  dependents, and print a built/failed/skipped summary (for a whole base set).
- **`--require-sandbox`** — fail a step that can't be network-isolated /
  filesystem-confined (fail-closed; default is best-effort + reported).
- **`--signing-key <path>`** — ed25519 seed (64 lowercase hex) to **sign**
  packages; without it, packages are produced UNSIGNED with a loud warning.
- **`SOURCE_DATE_EPOCH`** (env) — pin it for byte-identical reproducible output.

See the [building-packages guide](docs/guides/building-packages.md) and the
[base-system runbook](docs/guides/base-system-build.md).

## Security hardening

A recipe's `[security]` section selects compiler/linker hardening; takumi
generates the matching CFLAGS/LDFLAGS:

| Flag | CFLAGS/LDFLAGS | Effect |
|------|----------------|--------|
| `pie` | `-fPIE -pie` | Position-Independent Executable (ASLR) |
| `relro` | `-Wl,-z,relro` | RELRO (GOT protection) |
| `fullrelro` | `-Wl,-z,relro,-z,now` | Full RELRO (implies relro + bindnow) |
| `fortify` | `-D_FORTIFY_SOURCE=2` | Buffer-overflow detection |
| `stackprotector` | `-fstack-protector-strong` | Stack-smashing protection |
| `bindnow` | `-Wl,-z,now` | Immediate symbol binding |

Hardening is per-recipe; `fullrelro` dedups the implied `relro`/`bindnow`.

## Build order

`takumi order <dir>` resolves a dependency-aware topological order (Kahn's
algorithm) over the recipes in a directory, deterministically. `build --execute`
builds in that order; `--keep-going` surveys a whole set in one run.

## Dependencies (Cyrius stdlib)

takumi is pure Cyrius with no third-party dependencies — only vendored stdlib:

| Module | Purpose |
|--------|---------|
| `bayan` | Recipe parsing (`cyml_parse` splits header/body; `toml_parse` parses the header) |
| `sandhi` | HTTPS source download (HTTP/1.1+2, native TLS, streaming) |
| `sankoch` | Decompression (gzip / xz / bzip2) + DEFLATE for `.ark` |
| `sigil` | SHA-256 + ed25519 + hex |

## Related

- [ark](https://github.com/MacCracken/ark) — Package manager CLI (installs what takumi builds)
- [nous](https://github.com/MacCracken/nous) — Package resolver (resolves dependencies)
- [zugot](https://github.com/MacCracken/zugot) — Recipe repository (the recipes takumi reads)
- [sigil](https://github.com/MacCracken/sigil) — Trust verification (signs built packages)
- [AGNOS Philosophy](https://github.com/MacCracken/agnosticos/blob/main/docs/philosophy.md)

## License

GPL-3.0-only
