# 0012 — Build sandbox: Landlock filesystem confinement

- **Status**: accepted (takumi 0.10.0)
- **Date**: 2026-06-17
- **Builds on**: [ADR 0011](0011-build-sandbox.md) (sandbox: network + timeout),
  [ADR 0005](0005-build-execution.md) (build execution)

## Context

The sandbox's first bite (0.9.8) gave build steps a hermetic network namespace
and a wall-clock timeout, but left the filesystem open: a buggy or hostile
`install` could still write anywhere the unprivileged build user can reach
(its `$HOME`, world-writable dirs, …) — not just `$PKG`/DESTDIR. ADR 0005 named
filesystem confinement as a deferred sandbox limitation; this is that bite.

## Decision

Confine each build step's **writes** with **Landlock** (the Linux LSM for
unprivileged filesystem sandboxing, kernel 5.13+). Landlock is restrict-only (it
can only subtract from what the process already has), needs no privilege, and
survives `execve` — a perfect fit for "drop rights, then exec the recipe shell."

New code in `src/sandbox.cyr` (hand-rolled on the `sys_landlock_*` /
`sys_prctl` stdlib wrappers — no new dependency, consistent with the netns
bite):

- **`_sandbox_apply_landlock()`** (child-side, before `execve`): create a
  ruleset that *governs* the full ABI-1 write/create/remove/exec access set,
  then add `PATH_BENEATH` rules:
  - `/` → **read + traverse + execute** (the build reads the toolchain, headers,
    libs, and execs compilers — but cannot write);
  - `/tmp` → **read-write + create + remove** (this holds the build root and
    `$PKG`/DESTDIR — `_cli_build_root` is `/tmp/takumi-build`);
  - `/dev` → **read-write** (so `… >/dev/null` and friends work).

  Then `prctl(PR_SET_NO_NEW_PRIVS, 1)` and `landlock_restrict_self`. Net effect:
  the step can read/exec the whole system but can only **write** under `/tmp`
  and `/dev` — so `$PKG` works while `/usr`, `/etc`, `$HOME`, `/var`, … are
  read-only.
- **`sandbox_fs_available()`** (parent-side, no side effects): the
  version-query form of `landlock_create_ruleset` returns the supported ABI
  (≥ 1) or `-ENOSYS`/`-EOPNOTSUPP` on an old or LSM-disabled kernel.
- `exec_vec_sandboxed` gains a `confine_fs` flag (alongside `isolate_net`);
  `exec_build`/`_run_step` thread it; the CLI probes both layers once before the
  build loop and prints each mode.

**Best-effort, fail-open on setup, fail-closed on enforcement.** If Landlock is
unavailable, or any rule can't be added (which would leave a *broken* policy
that wedges the build), confinement is skipped and the step runs unconfined —
the CLI reports it. Once a complete ruleset is applied, it is enforced by the
kernel. This matches the netns bite and keeps takumi usable on kernels without
Landlock, transparently.

## Consequences

- A build step's writes are confined to the build/temp area; the rest of the
  filesystem is read-only to it. **Verified live**: with a negative control
  proving the target path is normally user-writable, a step's write to `$HOME`
  was **blocked** (`confined`, no file created) while its write to `$PKG`
  **succeeded** — both sandbox layers (netns + Landlock) active simultaneously.
- Tests (835, was 830): `sandbox_fs_available` returns a clean boolean, and the
  access-mask helpers are checked (RO excludes `WRITE_FILE`; RW includes
  `WRITE_FILE` + `MAKE_DIR`). The integration harness adds a tolerant Landlock
  case (escape blocked when confinement is active; otherwise just that the build
  ran). Enforcement can't be unit-tested in-process (it would restrict the test
  runner), so it is proven by the forked-child integration/live paths.
- **Policy is coarse by design (this bite).** Writable = all of `/tmp` + `/dev`,
  not *only* `$PKG`. This protects every system location (the actual goal) while
  keeping real recipes working (build trees + `mktemp` scratch live in `/tmp`).
  A tighter per-build policy (grant only the build root + a private tmp) is a
  future refinement.

## Scope / non-goals (this bite)

- Governs the **ABI-1** access set (5.13). `REFER`/`TRUNCATE`/`IOCTL_DEV`
  (ABI 2–4) are not separately governed — write protection already covers the
  cases they'd add for our policy.
- **No seccomp** syscall filtering yet; no PID/mount namespace; fixed timeout.
  Still hermeticity + confinement hardening, **not** a containment boundary
  against malicious recipes (recipes are trusted, sources sha-pinned).

## Alternatives considered

- **Vendor `agnosys` `security_apply_landlock`** — its mapping grants only
  `READ_FILE|READ_DIR|WRITE_FILE` for read-write paths (no `MAKE_*`/`REMOVE_*`),
  so a build couldn't *create* files in DESTDIR; and it pulls a large module +
  its `Result`/errno surface. Hand-rolling on the stdlib `sys_landlock_*`
  wrappers is smaller, dependency-free, and grants the create/remove rights a
  build actually needs.
- **mount-namespace bind-mounts / chroot instead of Landlock** — heavier,
  needs a mount namespace and careful teardown; Landlock is purpose-built and
  composes cleanly with the existing per-step fork.
- **Confine to only `$PKG`** — would break the common cases of writing into the
  extracted build tree and using `/tmp` scratch; revisit as a tighter opt-in.

## Amendment (0.11.3, audit SEC-09 / SEC-15)

The original policy granted read-write to **all of `/tmp`** + full `/dev`. The
security audit flagged this as broader than the stated guarantee. Revised:
Landlock now grants read-write on the **build root** passed from the CLI (the
build trees + DESTDIR live under it), `TMPDIR` is pointed inside the build dir so
build-tool scratch stays confined, and `/dev` is narrowed to **read/write of
existing nodes** (no `MAKE_*`/`REMOVE_*`). Per-step apply failure is now surfaced
(stderr warning) and, under `--require-sandbox`, fail-closed (SEC-08).
