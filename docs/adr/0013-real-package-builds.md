# 0013 — Real-package builds: extraction fidelity + build PATH

- **Status**: accepted (takumi 0.10.1)
- **Date**: 2026-06-17
- **Builds on**: [ADR 0002](0002-source-extraction-safety.md) (extraction),
  [ADR 0005](0005-build-execution.md) (build execution)

## Context

Build execution and its tests had only ever run *trivial* build steps (`cp`,
`grep`, writing a marker file). Attempting the first **real** build — GNU hello
via `./configure && make && make install`, on a host with a full toolchain —
surfaced three concrete defects that block essentially every real package. None
were caught earlier because no test had ever *executed an extracted file* or run
a compiler.

1. **Extraction dropped file modes.** `extract_archive` wrote every file at a
   fixed `0644` and never applied the tar header's mode (offset 100). A shipped
   `./configure` (0755) landed without `+x` → `./configure: Permission denied`
   (exit 126).
2. **Build environment had no `PATH`.** Steps `execve` with an empty environment
   (ADR 0005), and the prelude exported `PKG`/`CFLAGS`/… but not `PATH`. `gcc`
   ran but couldn't spawn `cc1`: `posix_spawnp: No such file or directory`
   (configure: "C compiler cannot create executables").
3. **Extraction dropped mtimes.** Files got the extraction wall-clock time, so
   `make` saw sources as newer than shipped generated files and tried to re-run
   autotools (`aclocal.m4`), failing with exit 127 when the toolchain wasn't
   present.

## Decision

- **Preserve the tar mode** (`src/source.cyr`): after writing a regular file,
  `chmod` it to `mode & 0777` (parsed from offset 100). The `& 0777` keeps rwx
  for all classes and **drops setuid/setgid/sticky** — a tarball must not be able
  to introduce those into the build tree.
- **Preserve the tar mtime**: `utimensat(AT_FDCWD)` sets atime+mtime from offset
  136, so `make`'s timestamp dependency logic sees the author's
  generated-vs-source ordering and doesn't spuriously regenerate.
- **Bake a standard `PATH`** into the build prelude (`src/build.cyr`):
  `/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`. Baked, not
  inherited, to keep builds reproducible (the empty-env design is unchanged;
  `PATH` is just part of the fixed prelude now, like `LC_ALL`).

## Consequences

- **takumi compiles real autotools packages end to end.** Verified live: GNU
  hello 2.12.1 fetched → verified → extracted → `./configure` → `make` (real C
  compilation) → `make install` → packaged, all inside the sandbox (network
  isolation + Landlock + timeout). The result is a real ELF x86-64 PIE binary
  that runs and prints `Hello, world!`; the `.ark` holds the installed tree.
- Tests (840, was 835): a fixture stamps mode `0755` + a fixed mtime; extraction
  is asserted to preserve both (`STAT_MODE & 0777`, `STAT_MTIME`). Integration
  adds a real `gcc`+`make` compile over loopback (gated on the toolchain), so CI
  proves real compilation without an external download.
- Mode preservation is faithful but **safe** (no setuid/setgid/sticky from a
  tarball). mtime preservation is deterministic (same tar → same times) and does
  not affect the `.ark` (the manifest carries no per-file mtime), so
  reproducibility (ADR 0010) is unchanged.

## On "build the full base system" (v1.0 criterion 1)

The pipeline can now build real packages; this is the capability criterion 1
needs. A *complete* 309-package base-system build is an **operator/CI activity**:
it requires a host with every package's build dependencies and is measured in
machine-hours, not something asserted in this repo's test run. takumi's side —
ordered, sandboxed, reproducible, real-compile builds — is demonstrated
end-to-end; driving the full set is downstream (zugot + a build host).

## Alternatives considered

- **Preserve the *exact* mode including special bits** — rejected; setuid/setgid
  from an untrusted tarball is a footgun for no benefit (build runs unprivileged
  into DESTDIR).
- **Inherit the operator's `PATH`** — rejected; non-reproducible and at odds with
  the empty-env model. A fixed prelude `PATH` is predictable; a per-recipe env
  override can come later if a recipe needs a non-standard toolchain location.
- **`touch`-ordering hack instead of real mtimes** — rejected; preserving the
  actual tar mtimes is the correct, general fix.

## Follow-ups

- Per-recipe environment / `PATH` override, if a real recipe needs tools outside
  the standard prefix.
- A multi-package "build report" (continue-on-error + summary) for driving large
  recipe sets — useful for the operator-side full base build.
