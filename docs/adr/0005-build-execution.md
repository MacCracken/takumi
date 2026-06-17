# 0005 — Build execution (unprivileged, DESTDIR-only)

- **Status**: accepted (takumi 0.9.1)
- **Date**: 2026-06-17

## Context

Running a recipe's `[build]` steps is takumi's reason to exist, and the
heaviest security surface before the v1 audit: it executes arbitrary shell from
recipes. Everything around it already existed (parse/validate, source
verify/extract, `BuildContext`/`BuildStatus`/`BuildLogEntry`, hardening-flag
generation, the `.ark` writer). 0.9.1 adds the executor (`src/build.cyr`) and
records the safety model here.

## Decision

`exec_build(ctx, started) -> BuildLogEntry` runs the six phases in order
(pre_build → configure → make → check → install → post_install), skipping empty
steps, advancing `BuildStatus`, **fail-closed** (stop at the first non-zero
exit; never package a partial fake-root). Each step runs as:

```
exec_vec(["/bin/sh", "-c", wrapped])
```
where `wrapped` is a newline-separated script: `cd '<cwd>' || exit 1`, the env
prelude (`export PKG`/`DESTDIR` = the fake-root, `CFLAGS`/`LDFLAGS` from
hardening, `MAKEFLAGS=-j1`, `LC_ALL=C`, `umask 022`), then the step verbatim.
`exec_vec` inherits stdout/stderr (build output is visible; `exec_env` was
rejected for muffling stderr), reaps its child, and returns the exit code
(127 = sh/exec-not-found, negative = fork/abnormal). All prelude values are
single-quoted (`_sh_squote`). `stage_build_dirs` lays out
`build_root/<pkg>/{src,build,pkg}` and empties the fake-root before a build.

### Why newline-separated, not `&& { …; }`

An early attempt wrapped the step as `{ <step>\n; }`; the `;` after a newline
with no preceding command is a **sh syntax error**, so every non-empty step
failed (caught by the hermetic tests). Newline separation runs each line as its
own command, lets steps span multiple lines / backslash-continuations, and
makes the script's exit code equal the step's.

## Security model

- **Core invariant — unprivileged + DESTDIR-only.** configure/make/check/install
  all run as the invoking build user and write *only* into the fake-root
  (`PKG`/`DESTDIR`). takumi build never writes to `/` and needs **no root and no
  setuid helper**. This is the deliberate contrast with ark, whose *install*
  path touches `/usr`,`/etc` and is mediated by the setuid `shakti` helper. The
  privilege boundary lives entirely downstream; the build phase has no business
  outside its scratch tree.
- **Command injection is by design.** Recipe `[build]` steps *are* shell
  scripts; running them verbatim is the point. takumi adds no injection beyond
  its fixed, single-quoted `cd`/`export` prelude. Trust model: curated zugot
  recipes + sha-pinned, verified sources (the standard from-source posture of
  Gentoo ebuilds / Arch PKGBUILDs / BSD ports).
- **Documented v1 limitations (deferred to a future sandbox milestone):**
  - No filesystem/mount sandbox — a buggy/malicious `install` can write outside
    DESTDIR within the build user's reach. Operator mitigation: a dedicated,
    unprivileged, throwaway build user.
  - No network namespace — a step may fetch at build time, defeating source
    pinning/reproducibility.
  - No rlimit/timeout — a runaway step blocks indefinitely.
  These need `unshare`/`clone` and rlimit syscalls not yet wrapped in the
  stdlib; the sandbox is a post-v1 milestone. `umask 022` is the one hardening
  taken now.
- **Fail-closed** stops on the first failing step and returns before packaging,
  mirroring the extractor (ADR 0002).

## CLI

`takumi build <dir>` stays a dry-run plan by default (exit 2); `--execute`/`-x`
runs the build per topo order under a scratch build root, packaging each
`BS_COMPLETE` result into an unsigned `.ark`. Recipes whose source isn't staged
(download still deferred) are **skipped, not failed** ("source not staged
(download pending)"); a `BS_FAILED` build stops the run (exit 1). Local
meta-packages (no source, empty steps) build trivially and package.

## Consequences

- takumi can now produce a real `.ark` from a recipe end-to-end (demonstrated
  for local meta-packages and any pre-staged source; full coverage waits on the
  download item).
- Reproducibility knobs (`MAKEFLAGS=-j1`, `LC_ALL=C`) are set; deeper
  reproducibility + the sandbox are future work.
- The executor is fully unit-tested hermetically with trivial shell steps
  (success populates the fake-root, failure is fail-closed, meta completes,
  empty steps skip), and a test chains a completed build through
  `create_file_list → create_ark_manifest → ark_write → ark_read`.

## Alternatives considered

- **`exec_env` for env** — rejected; it muffles stderr (undebuggable builds).
- **Run privileged / install to `/`** — rejected; building never needs root.
  Staging into DESTDIR and packaging keeps the whole phase unprivileged.
- **Sandbox now** — deferred; needs unwrapped namespace/rlimit syscalls and is
  its own milestone. Documented honestly rather than half-built.
