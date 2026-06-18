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

Takumi is a multi-file Cyrius binary under `src/*.cyr` (entry `src/main.cyr` →
`src/cli.cyr`). The logical model:

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

## Entry point (`src/main.cyr` → `src/cli.cyr`)

`main` initializes the allocator, reads `argv`, and calls `cli_dispatch(args)`,
which returns the process exit code. Commands: `validate <recipe.cyml>...`,
`list <dir>`, `order <dir>`, `build <dir> [--execute|-x] [--keep-going|-k]
[--require-sandbox] [--signing-key <path>]`, `version`, `help`. `build` without
`--execute` prints the plan (exit 2); with it, runs the full pipeline. Dispatch
is a plain function over a vec of cstrs (no `argv` access) so every command is
unit-testable by exit code. Exit codes: `0` ok, `1` operational error, `2` usage.
See [ADR 0003](../adr/0003-cli-surface.md).

## Data Flow

```
0. CLI:      argv -> cli_dispatch -> command (validate/list/order/build/...)
1. Load:     .cyml files -> CymlDoc (cyml_parse) -> TOML header (toml_parse) -> BuildRecipe structs
2. Validate: BuildRecipe -> Result<warnings> (reject malformed early)
3. Resolve:  [package names] -> topological build order (Kahn's algorithm)
4. Source:   fetch_source (HTTPS via sandhi, src/fetch.cyr) -> verify_source_hash
             (SHA-256 vs recipe) -> extract_archive (.tar/.gz/.xz/.bz2,
             path-traversal-guarded) -> source tree (src/source.cyr)
4b. Patch:   apply_patches applies source.patches to the extracted root via
             `patch -p1` (src/build.cyr), after extract, before build
5. Build:    exec_build runs [build] steps via /bin/sh -c (unprivileged) -> fake-root (src/build.cyr)
6. Package:  installed files -> ArkManifest + ArkFileEntry list (src/package.cyr,
             symlink-aware) -> serialized .ark v1 (src/ark_format.cyr): TOML
             manifest + file index + DEFLATE data + SHA-256 root + ed25519 signature
```

### Source acquisition (`src/source.cyr`)

A recipe's `[source]` is one of three kinds (`SourceSpec.kind`, see
[ADR 0004](../adr/0004-recipe-source-model.md)): a plain `url` + `sha256`, a
`github_release` + `release_asset` + `sha256`, or `local = true` (a meta/alias
package with no upstream). `fetch_source` (`src/fetch.cyr`, HTTPS via stdlib
`sandhi` with the native TLS backend) downloads `url`/`github_release` sources —
resolving a GitHub asset via the releases API + glob match — then the hard
sha256 gate runs before extraction ([ADR 0006](../adr/0006-source-download.md)).
The artifact is **streamed** straight to disk (`sandhi_http_download`), so source
size is bounded only by disk + a wall-clock timeout, not by a fixed in-memory
cap ([ADR 0010](../adr/0010-streaming-download.md)).
`verify_source_hash(path, expected_sha256)` confirms a staged tarball matches the
recipe's `source.sha256`; `extract_archive(archive, dest)` unpacks `.tar`,
`.tar.gz`, `.tar.xz`, and `.tar.bz2` (all via stdlib `sankoch` — gzip
ISIZE-sized, xz/bz2 grow-retry) with a fail-closed path-traversal guard
(rejects `..`, absolute paths, and escaping symlink targets; unsupported tar
entry types abort). Both the POSIX `ustar` and the pre-POSIX `v7` tar layouts
are accepted — headers are validated by **checksum**, not the `ustar` magic, so
magic-less v7 tarballs (real GNU release tarballs) extract
([ADR 0008](../adr/0008-v7-tar-checksum-gated-headers.md)). Long paths via both
mechanisms extract — POSIX.1-2001 **PAX** (`x`/`g`: `path`/`linkpath`/`size`)
and **GNU** `L`/`K` long-name headers — each applied through the same
path-traversal guard ([ADR 0009](../adr/0009-pax-extended-headers.md)). The full
real-world matrix is covered: ustar + v7 + PAX + GNU, across gz/xz/bz2. The
extraction safety model is in
[ADR 0002](../adr/0002-source-extraction-safety.md).

### Build execution (`src/build.cyr`)

`exec_build(ctx, started)` runs the recipe's six `[build]` phases via
`/bin/sh -c` — inside the extracted source root (`_build_cwd` descends into the
tarball's single top-level dir) (env baked into a single-quoted prelude: `PKG`/`DESTDIR` =
fake-root, `CFLAGS`/`LDFLAGS`, `MAKEFLAGS=-j1`, `LC_ALL=C`, `umask 022`),
advancing `BuildStatus`, fail-closed, returning a `BuildLogEntry`. The whole
build runs **unprivileged** and writes only into the DESTDIR fake-root — no
root, no setuid helper (the privilege boundary is downstream in ark/shakti).
`stage_build_dirs` lays out `build_root/<pkg>/{src,build,pkg}`. CLI: `build
--execute`. Security model in [ADR 0005](../adr/0005-build-execution.md). Each
step runs through the **sandbox** (`src/sandbox.cyr`, `exec_vec_sandboxed`): a
fresh **network namespace** (unprivileged user-namespace + identity uid/gid map;
hermetic — no build-time network), **Landlock filesystem confinement** (writes
restricted to the **build root** + existing `/dev` nodes, with `TMPDIR` pointed
inside it, so the rest of the filesystem is read-only to the step), and a
**wall-clock timeout** (process-group `SIGKILL` on overrun). Isolation/
confinement are best-effort + probed/reported (or fail-closed with
`--require-sandbox`); the timeout always applies. seccomp is a post-1.0 bite. See
[ADR 0011](../adr/0011-build-sandbox.md) + [ADR 0012](../adr/0012-landlock-fs-confinement.md). Before the build steps,
`apply_patches(recipe, cwd, patch_dir)` applies the recipe's `source.patches`
(in order) to the extracted source root by shelling out to the system `patch`
(`patch -p1 -d <cwd> -i <file>`, fail-closed); patch files resolve under the
recipes directory. See [ADR 0007](../adr/0007-patch-application.md).

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

Pure Cyrius; no third-party dependencies — only vendored stdlib modules:

| Module | Purpose |
|--------|---------|
| `bayan` | Recipe parsing — `cyml_parse` splits header/body, `toml_parse` parses the header |
| `sandhi` | HTTPS source download (HTTP/1.1+2, native TLS, streaming to disk) |
| `sankoch` | Decompression (gzip / xz / bzip2) + DEFLATE for the `.ark` data section |
| `sigil` | SHA-256 (`sha256_digest`), ed25519 signing/verify, hex |
| `chrono` (stdlib) | Build timestamps (`clock_epoch_secs`) |
