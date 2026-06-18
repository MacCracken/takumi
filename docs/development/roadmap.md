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
