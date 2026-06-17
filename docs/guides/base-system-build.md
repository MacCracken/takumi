# Building a base system (operator runbook)

How to drive a whole recipe set (e.g. the AGNOS base system from
[zugot](https://github.com/MacCracken/zugot)) through takumi on a build host.

For the recipe format and a single-package walkthrough, see
[Building packages](building-packages.md).

## Prerequisites

A dedicated, **unprivileged, throwaway build user** on a Linux host with:

- A C/C++ toolchain and the usual build tools (`gcc`/`cc`, `make`, `ld`, `ar`,
  `tar`, `patch`, …) for whatever the recipes compile. takumi runs build steps
  with a fixed `PATH` (`/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`),
  so tools must be reachable there.
- Each recipe's declared **build dependencies** already installed (takumi orders
  by runtime deps but does not itself install build deps).
- **Unprivileged user namespaces** enabled (for network isolation) and
  **Landlock** (kernel 5.13+, for filesystem confinement) — both optional but
  recommended; takumi reports which are active and proceeds best-effort without
  them.
- Free disk under `/tmp` (the build root is `/tmp/takumi-build`; sources stream
  to disk there, and DESTDIR fake-roots + `.ark` outputs live under it).

## One command

```sh
SOURCE_DATE_EPOCH=$(date +%s) \
  takumi build /path/to/zugot --keep-going --execute
```

This validates every recipe, resolves the **topological build order** (Kahn's
algorithm over runtime deps), then builds each package in order:

```
fetch → verify (sha256) → extract → patch → build (sandboxed) → package (.ark)
```

Outputs land in `/tmp/takumi-build/out/<name>.ark`.

### Flags that matter for a base build

- **`--execute` (`-x`)** — actually run the pipeline (without it, `build` prints
  the plan and exits 2).
- **`--keep-going` (`-k`)** — attempt **every** package instead of stopping at
  the first failure. A failed package's dependents are **skipped** (not
  cascade-failed), and a summary is printed at the end. Without it, the build is
  fail-closed: the first failure stops the run (right for CI gates; `-k` is right
  for surveying a large set).
- **`SOURCE_DATE_EPOCH`** — pin it for **reproducible** `.ark` output (same
  recipe + sources + epoch → byte-identical package). Unset uses the wall clock.

## Reading the report

With `--keep-going`, each package prints `build: ok -> …`, `build: FAILED: …`
(with the failing phase, e.g. `make failed (exit 2)`), or
`build: skipped (dependency failed): …`, followed by:

```
build summary: 312 built, 2 failed, 5 skipped (of 319)
  failed:  libfoo bar
  skipped: usesfoo a b c d
```

- **built** — produced a verified, signed `.ark`.
- **failed** — a stage failed; the per-package line above names which.
- **skipped** — a runtime dependency failed or was skipped, so the package
  wasn't attempted (fix the root cause and re-run).

**Exit code**: `0` only if nothing failed; `1` if any package failed (so CI can
gate on it even in `--keep-going` mode).

## The sandbox

Each build step runs in the sandbox (reported at the top of the run):

- **Network isolation** (fresh netns) — hermetic; the build can't fetch
  un-pinned inputs. Sources are already fetched + verified.
- **Filesystem confinement** (Landlock) — writes restricted to the build/temp
  area; `/usr`, `/etc`, `$HOME`, … are read-only to the build.
- **Wall-clock timeout** — a runaway step is killed (whole process group).

These are best-effort + reported; the timeout always applies. This is
hermeticity + confinement + liveness hardening, **not** a containment boundary
against malicious recipes — run as a throwaway unprivileged user over curated,
sha-pinned recipes.

## Tips

- **Iterate on failures**: re-run with `--keep-going` after fixing a root-cause
  package; previously-skipped dependents will be attempted once their dep builds.
- **Reproducibility check**: build twice with the same `SOURCE_DATE_EPOCH` and
  compare `.ark` bytes — they must be identical.
- **Clean slate**: the build root (`/tmp/takumi-build`) is reused; remove it
  between full runs if you want a pristine survey.
