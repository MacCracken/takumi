# Development Roadmap

takumi **1.0.0** has shipped: a complete, hardened, reproducible, signed build
pipeline (parse → fetch → verify → extract → patch → sandboxed build → sign).
The full history of how it got here is in [`CHANGELOG.md`](../../CHANGELOG.md)
and git; this file tracks only **forward-facing** work.

> Process for each item below: one bounded feature per release, fully
> built + tested + benchmarked + documented, per [`CLAUDE.md`](../../CLAUDE.md).

## Sandbox hardening (post-1.0)

The build sandbox ships with network isolation + Landlock filesystem confinement
+ a wall-clock timeout (best-effort + reported, or fail-closed via
`--require-sandbox`). Remaining hardening:

- [ ] **PID namespace for the build step** — closes the documented residual
      **SEC-11** (a step that double-forks / `setsid`s escapes the timeout's
      process-group kill). Needs a double-fork PID-1 reaper. See
      [security-audit-2026.md](../compliance/security-audit-2026.md) +
      [ADR 0011](../adr/0011-build-sandbox.md).
- [ ] **seccomp syscall filtering** — restrict the syscall surface of build
      steps (deferred from the audit as a post-1.0 enhancement).
- [ ] **Mount namespace** — a private view of the filesystem for the build step.
- [ ] **Tighter Landlock write area** — confine to the per-package build dir +
      DESTDIR rather than the whole build root.
- [ ] **Per-recipe build timeout override** — currently a fixed per-step ceiling.

## Signing / supply chain (post-1.0)

- [ ] **`--require-signing`** — fail-closed when no signing key is supplied
      (mirrors `--require-sandbox`); today an unsigned build warns loudly.
- [ ] **Key management ergonomics** — key rotation guidance; optional
      hardware-backed / external signer.

## Sovereign build on AGNOS (ark v2 path — M5/M6, server-stage)

takumi's share of the **ark v2 sovereignty path** — the BUILD half of self-hosting
("build agnos on agnos"), the deepest gate. Orchestration spine:
[`agnosticos/docs/development/planning/ark-v2-sovereignty-path.md`](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/ark-v2-sovereignty-path.md).
**Server-stage** (agnos has no shell/fork/namespace), gated on the agnos build-surface
items filed as **agnos 1.51.x (c)/(d)/(e)**. Today every build step runs via
`exec_vec(['/bin/sh','-c', wrapped])` (`src/build.cyr:25,136,236`) + shells out to
`/bin/rm`, `patch -p1` (`build.cyr:155`); the sandbox needs `sys_fork`×4 /
`unshare(CLONE_NEWUSER|NEWNET)` / Landlock / `/proc/*/uid_map` — agnos has none.

- [ ] **M5 — agnos-native build-step executor**: replace `/bin/sh -c` with a structured
      step executor over agnos's exec surface only (`spawn#3`/`execwait#37`/`spawn_path#43`
      run-to-completion ELF + `exec_redirect#62` + `waitpid#4`). **Needs agnos 1.51.x:**
      nested exec from a spawned proc (execwait#37 refuses re-entry → drive `spawn_path#43`
      + poll-`waitpid#4`), and argv/env cap raises (127 B path+argv, 1024 B/16-entry env are
      too small for build invocations). Drop the `/bin/rm`/`patch` shell-outs for native FS ops.
- [ ] **Build confinement on agnos**: either an **agnos-native capability-bounded sandbox**
      (matches the capability-per-action posture; **converges with Phase 20 / agnos 1.51.x (e)
      "Native sandbox-confinement primitives" — consume that, don't double-build**), or an
      explicit no-op-with-warning at server bring-up. Resolve what `--require-sandbox`
      fail-closed *means* on agnos.
- [ ] **Native store/index writer (M2 producer side)**: index built `.ark`s into the
      content-addressed local store + signed native index nous/ark resolve against (the
      producer gate that makes M2's store non-empty). Define the format with zugot.
- [ ] **M6 — self-host**: drive zugot's `build-order.txt` (225-pkg topo) through the native
      executor on a booted agnos; the `marketplace/MacCracken/*` set (builds via `cyrius build`)
      is the first proving ground. Acceptance: agnos rebuilds a slice of its own base from
      zugot recipes, indexes the `.ark`s natively, nous resolves, ark installs — apt-free, QEMU + iron.

## Recipe + build features

- [ ] Parallel builds for independent packages
- [ ] Build caching / ccache integration
- [ ] Cross-compilation support
- [ ] `noarch` package support (scripts, docs, fonts)
- [ ] Epoch field for version comparison
- [ ] `provides` / `conflicts` / `replaces` fields
- [ ] Multiple source URLs per recipe (mirror/fallback)
- [ ] Explicit `backup` file list (beyond the `/etc/` heuristic)
- [ ] Build options / feature flags per recipe
- [ ] `size_compressed` in the manifest

## Format / tooling

- [ ] Fuzz harness for the tar/PAX/GNU + `.ark` parsers — blocked on a Cyrius
      AFL/libFuzzer equivalent (re-check when the toolchain ships one).
- [ ] gzip multi-member grow-retry (correctness limit noted as SEC-18: a
      multi-member `.tar.gz` whose last-member ISIZE under-sizes the buffer is
      rejected rather than grown). Low priority — single-member is the norm.

## Known residuals (accepted at 1.0)

- **SEC-11** (timeout escape via double-fork) — documented; closed by the PID
  namespace item above. The build is unprivileged + DESTDIR-only and recipes are
  trusted, so this is defense-in-depth, not a containment hole.
- The sandbox is **not** a containment boundary against a *malicious* recipe
  (recipes are trusted/curated). See the audit's threat model.
