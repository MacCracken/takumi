# 0007 — Patch application (shell out to `patch`)

- **Status**: accepted (takumi 0.9.4)
- **Date**: 2026-06-17

## Context

Recipes carry an ordered `source.patches` list (`SourceSpec`, ADR 0004) — local
`.patch` files that fix or adapt the upstream source before it builds. Until now
takumi parsed and validated the list but never applied it: the pipeline went
**fetch → verify → extract → build** with patches silently ignored. Real-world
recipes (Linux distro ports) routinely patch upstream sources, so an unapplied
patch list is a correctness hole — the package builds from pristine, un-fixed
source.

0.9.4 closes that: apply each patch to the extracted source tree after extract,
before build, making the pipeline **fetch → verify → extract → patch → build →
package**.

## Decision

`src/build.cyr` — `apply_patches(recipe, cwd, patch_dir)` applies each entry of
`source.patches` in list order to the extracted source root (`cwd`,
`_build_cwd` — the same single-top-level-dir-aware path build steps run in),
resolving each patch file under `patch_dir` (the recipes directory). It shells
out to the system **`patch`** via `/bin/sh -c`:

```
patch -p1 -d <cwd> -i <patch_dir>/<file>
```

- **`-p1`** strips the leading `a/` `b/` path component — the universal
  convention for `git diff` / `diff -u a b` output, which is what recipe patches
  are.
- **`-d <cwd>`** applies inside the extracted source root, so patch paths resolve
  exactly as the build steps' working directory sees them.
- Both `cwd` and the patch path are single-quoted (`_sh_squote`, the same
  helper the build prelude uses) so a pathological path can't break the shell
  word.

**Fail-closed.** `apply_patches` returns `0` on success, or `0 - (index + 1)` of
the first patch that fails to apply (non-zero `patch` exit). The CLI
`_cli_build_execute` treats any non-zero return as a build failure and stops
before `exec_build` — a recipe whose patch doesn't apply never produces a
package. No patches → no-op → `0`.

**Same shell-out posture as build execution (ADR 0005).** Recipes are trusted,
curated build scripts over sha-pinned, verified sources; the patch files ship in
the (trusted) recipe repo. Applying them is no greater a trust surface than the
arbitrary `[build]` shell steps takumi already runs. `patch` is the
industry-standard unified-diff applier, present on every build host — reusing it
is consistent with shelling out to `/bin/sh` for the build, and avoids
reimplementing a diff/hunk engine in-tree.

## Consequences

- `build --execute` now applies a recipe's `source.patches` to the extracted
  tree before building. Recipes that previously built from un-patched source now
  build from the intended, patched source.
- Patch files resolve relative to the **recipes directory** (the `dir` argument
  to `build`), alongside the `.cyml`. This matches how distro recipe trees keep
  a recipe and its patches together.
- **Runtime dependency: `patch`** on the build host (POSIX-standard; already
  implied by the `/bin/sh` + coreutils build environment).
- Tests: a hermetic round-trip applies a genuine unified diff via the real
  `patch` tool and asserts the file content changed, plus a non-applying patch
  (context mismatch) returns non-zero (fail-closed). The integration harness
  (`scripts/integration.sh`, needs `python3`+`tar`+`diff`) drives the full
  **fetch → verify → extract → patch → build → package** path over a loopback
  server with a `diff`-generated patch and asserts the build observed the change.
- **Verified against a real project.** The full pipeline was confirmed live
  against **GNU hello 2.12.1** source with a real unified diff against
  `src/hello.c` (greeting string): fetch → verify (sha256) → extract → patch
  (`patching file src/hello.c`) → build → package, with the patched source
  landing in the fake-root.

## Known limitations / follow-ups

- **Fixed `-p1` strip level.** Recipe patches are assumed to be `a/`…`b/`-style
  unified diffs (the near-universal convention). A configurable strip level
  (`-pN`) waits for a recipe that needs it.
- **No fuzz/offset control, no `--dry-run` pre-check, no reverse-apply
  detection** — a patch either applies cleanly or the build fails. Good enough
  for curated recipes; revisit if recipe authors need looser application.
- **v7 (pre-POSIX) tar extraction** — surfaced while confirming this feature
  against GNU hello: GNU release tarballs are often old **v7** tar (no `ustar`
  magic at offset 257), which `extract_archive` currently rejects
  (`SRC_ERR_BAD_MAGIC`) before patches can run. This is an *extraction*-layer
  gap (ADR 0002), tracked separately on the roadmap; the GNU hello e2e above was
  confirmed by serving the same real source in a ustar tarball.

## Alternatives considered

- **Reimplement a unified-diff applier in Cyrius** — rejected. A correct hunk
  engine (context matching, offsets, fuzz) is a large, bug-prone surface; `patch`
  is battle-tested and already present. Consistent with the ADR 0005 decision to
  shell out for build steps rather than reimplement a shell.
- **Apply patches via `git apply`** — rejected. Adds a `git` dependency and a
  working-tree assumption; `patch` is lighter and ubiquitous.
- **Apply before extract / as a fetch step** — nonsensical; patches target the
  extracted tree. Placed after extract, before build, inside the build cwd.
