# Building packages with takumi

This guide takes you from a CYML recipe to a signed `.ark` package.

## Build the tool

```sh
cyrius build src/main.cyr build/takumi
./build/takumi version
```

## What a recipe is

A recipe is a **CYML** file (`.cyml`): a TOML header (structured metadata) above
an optional `---`, with a markdown body below for prose build notes. takumi
reads only the header. Recipes live in the
[zugot](https://github.com/MacCracken/zugot) repository.

### Recipe anatomy

```toml
[package]
name = "hello"            # required; safe name (letters, digits, - _ + .)
version = "2.12.1"        # required
description = "GNU hello" # required
license = "GPL-3.0-only"  # required
groups = ["base"]         # optional
release = 1               # optional (default 1)
arch = "x86_64"           # optional (defaults to the builder arch)

[source]
# Exactly one of three source kinds:
#   1. a direct URL (https only) + its sha256
url = "https://ftp.gnu.org/gnu/hello/hello-2.12.1.tar.gz"
sha256 = "8d99142afd92576f30b0cd7cb42a8dc6809998bc5d607d88761f512e26c7db20"
#   2. a GitHub release:  github_release = "owner/repo"
#                         release_asset  = "name-*-glob.tar.gz"   (sha256 still required)
#   3. a meta/alias package with no upstream:  local = true
patches = ["fix-build.patch"]   # optional; applied with `patch -p1` after extract

[depends]
runtime = ["glibc"]       # runtime dependencies
build = ["gcc", "make"]   # build-time dependencies

[build]
# Six shell phases, run in order inside the extracted source root. All optional;
# empty/absent phases are skipped. They are arbitrary /bin/sh — by design.
pre_build   = ""
configure   = "./configure --prefix=/usr"
make        = "make"
check       = "make check"
install     = "make DESTDIR=$PKG install"
post_install = ""

[security]
hardening = ["pie", "fullrelro", "fortify", "stackprotector", "bindnow"]
cflags = "-O2 -pipe"
ldflags = "-Wl,--as-needed"
```

The source kind, name safety, `https://` scheme, and sha256 format are validated
strictly — malformed recipes are rejected early (`takumi validate`).

## The CLI

| Command | What it does |
|---------|--------------|
| `takumi validate <recipe.cyml>...` | Parse + validate; reports errors/warnings. |
| `takumi list <dir>` | List recipes in a directory (`name  version`). |
| `takumi order <dir>` | Print the topological build order for a recipe tree. |
| `takumi build <dir>` | Print the build plan (dry run). |
| `takumi build <dir> --execute` | Run the full pipeline and write `.ark`s. |
| `takumi version` / `takumi help` | Version / usage. |

Exit codes: `0` success, `1` operational error (bad input, invalid recipe,
dependency cycle), `2` usage error.

## The build pipeline (`--execute`)

For each package, in dependency order:

```
parse → fetch → verify (sha256) → extract → patch → build → package (.ark)
```

1. **Fetch** the source over HTTPS (native TLS, no libssl). The artifact is
   **streamed** to disk, so source size is bounded only by disk + a wall-clock
   timeout (no in-memory cap). `local = true` recipes skip this.
2. **Verify** the download against the recipe's `sha256` — a **hard gate**: a
   mismatch aborts the build before anything is extracted.
3. **Extract** the tarball (`.tar`, `.tar.gz`, `.tar.xz`, `.tar.bz2`; `ustar`,
   pre-POSIX `v7`, and PAX layouts), with a fail-closed path-traversal guard.
4. **Patch** — apply each `source.patches` entry with `patch -p1`, in order,
   inside the extracted root.
5. **Build** — run the `[build]` phases (see below).
6. **Package** — hash + sign the fake-root into a `.ark`.

Outputs land in `/tmp/takumi-build/out/<name>.ark`.

## The build environment

Build phases run inside the extracted source root (takumi descends into the
tarball's single top-level directory automatically). Before each phase, takumi
exports a fixed prelude:

- `PKG` and `DESTDIR` — the **fake-root** to install into. **Install into
  `$PKG`/`$DESTDIR`, never into `/`.** takumi packages exactly what lands here.
- `CFLAGS` / `LDFLAGS` — hardening flags generated from `[security]` plus your
  `cflags`/`ldflags`.
- `MAKEFLAGS=-j1`, `LC_ALL=C`, `umask 022` — reproducibility knobs.

The whole build runs **unprivileged** and writes only into the fake-root — no
root, no setuid helper.

## The build sandbox

Each build step runs in the sandbox:

- **Network isolation** — the step runs in a fresh network namespace (no
  external connectivity). Sources are already fetched + verified, so builds are
  hermetic: a step cannot fetch un-pinned inputs. Created unprivileged via a user
  namespace; best-effort (where unprivileged user namespaces are unavailable the
  step runs un-isolated, and `build --execute` says so).
- **Filesystem confinement (Landlock)** — the step can read and execute the
  whole system (toolchain, headers, libs) but can only **write** under `/tmp`
  (which holds the build root and `$PKG`/DESTDIR) and `/dev`. So `/usr`, `/etc`,
  `$HOME`, and the rest are read-only to the build — a buggy `install` can't
  escape DESTDIR. Best-effort (reported when unavailable).
- **Wall-clock timeout** — a runaway step is killed (whole process group), so a
  hung build can't wedge the builder.

`build --execute` prints which layers are active. This is hermeticity +
confinement + liveness hardening, not a containment boundary against malicious
recipes (recipes are trusted, sources are sha-pinned).

## Reproducible builds

The `.ark` writer is deterministic. The only otherwise-floating input is the
build timestamp, which honors **`SOURCE_DATE_EPOCH`**
([reproducible-builds.org](https://reproducible-builds.org/docs/source-date-epoch/)):

```sh
SOURCE_DATE_EPOCH=1700000000 takumi build recipes/ --execute
```

The same recipe + sources + `SOURCE_DATE_EPOCH` produce a **byte-identical**
`.ark`. When `SOURCE_DATE_EPOCH` is unset, the wall-clock time is used.

## Try it

A complete, annotated example is in
[docs/examples/hello](../examples/hello/) — GNU hello with a real patch.
