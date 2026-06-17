# Example: GNU hello (URL source + a patch)

A complete recipe that fetches GNU hello from its canonical mirror, applies a
real patch to the source, builds it, and packages a `.ark`. It exercises every
stage of the pipeline.

Files:

- [`recipe.cyml`](recipe.cyml) — the recipe.
- [`greeting.patch`](greeting.patch) — a unified diff against `src/hello.c`.

## The recipe, annotated

```toml
[source]
url = "https://ftp.gnu.org/gnu/hello/hello-2.12.1.tar.gz"
sha256 = "8d99142afd92576f30b0cd7cb42a8dc6809998bc5d607d88761f512e26c7db20"
patches = ["greeting.patch"]
```

- **`url` is `https://`** — required for the `url` source kind.
- **`sha256`** is the hash of the *pristine upstream tarball*. takumi verifies
  the download against it **before** extracting — a mismatch aborts the build.
  (This is GNU hello 2.12.1's published hash, and notably it ships in the
  pre-POSIX **v7** tar format — takumi handles that.)
- **`patches`** are applied with `patch -p1` *after* extraction, *before* the
  build, resolved relative to the recipe directory.

```toml
[build]
configure = "./configure --prefix=/usr"
make = "make"
install = "make DESTDIR=$PKG install"
```

- Phases run inside the extracted source root (`hello-2.12.1/`).
- `install` writes into **`$PKG`** (the fake-root) via `DESTDIR` — never into
  `/`. takumi packages exactly what lands under `$PKG`.

## The patch

`greeting.patch` is an ordinary unified diff (the `a/` `b/` prefixes are why we
apply with `-p1`). It changes hello's greeting string:

```diff
-  greeting_msg = _("Hello, world!");
+  greeting_msg = _("Hello from a takumi patch!");
```

## Build it

```sh
# Put recipe.cyml + greeting.patch in a directory, then:
takumi build path/to/recipe-dir --execute
```

You'll see:

```
build plan (in order):
  hello
build: network isolation: active (hermetic; build steps have no network)
patching file src/hello.c
build: ok -> /tmp/takumi-build/out/hello.ark
```

`patching file src/hello.c` confirms the patch applied; the build then runs in a
network-isolated, time-bounded sandbox and produces a signed `hello.ark`.

## Make it reproducible

```sh
SOURCE_DATE_EPOCH=1700000000 takumi build path/to/recipe-dir --execute
```

Run twice with the same `SOURCE_DATE_EPOCH` and the two `hello.ark` files are
byte-identical.
