# 0011 — Build sandbox: hermetic network + wall-clock timeout

- **Status**: accepted (takumi 0.9.8)
- **Date**: 2026-06-17
- **Builds on**: [ADR 0005](0005-build-execution.md) (build execution; this is the
  first installment of its deferred sandbox)

## Context

Build execution (0.9.1, ADR 0005) runs a recipe's shell steps unprivileged into
a DESTDIR fake-root, but with **no** sandbox: a step had full network access and
no time bound. ADR 0005 named both as deferred. Two concrete gaps:

- **Non-hermetic builds.** Sources are already fetched + sha256-verified before
  the build, so a build needs no network — yet a step could fetch un-pinned
  inputs (breaking reproducibility) or exfiltrate. A reproducible build system
  should cut the build step's network.
- **No liveness bound.** A hung or looping step (`./configure` waiting on a dead
  mirror, an infinite `make`) wedges the builder forever.

This is the first sandbox bite (scope chosen deliberately small per the
large-item discipline): **network isolation + timeout**. Filesystem confinement
(Landlock) and seccomp are separate, later bites.

## Decision

New `src/sandbox.cyr` — `exec_vec_sandboxed(args, timeout_ms, isolate_net)`,
which `_run_step` (`src/build.cyr`) now calls instead of `exec_vec`. It composes
the existing fork/exec/wait shape (`lib/process.cyr`, `lib/regression.cyr`),
Linux + unprivileged:

- **Network isolation (`isolate_net = 1`).** In the forked child, before
  `execve`: `unshare(CLONE_NEWUSER | CLONE_NEWNET)`. The user namespace makes
  this work **unprivileged**; the network namespace has no external
  connectivity (only a down loopback). An **identity uid/gid map** (`<id> <id>
  1` via `/proc/self/uid_map` + `gid_map`, after `setgroups=deny`) keeps the
  build's real, non-root identity so created files have correct ownership —
  matching takumi's no-root, DESTDIR-only model. Best-effort: if `unshare` is
  refused, the step runs un-isolated.
- **Wall-clock timeout (always).** The child leads a new session (`setsid`) so
  it heads its own process group; the parent polls `waitpid(WNOHANG)` and, past
  `SANDBOX_TIMEOUT_MS` (1 h per step), `SIGKILL`s the whole **process group**
  (so `make`'s children die too) and reports `0 - 2` (→ "terminated
  abnormally"). Mirrors `lib/regression.cyr`'s bounded-run loop.
- **Capability probe + transparency.** The CLI calls `sandbox_net_available()`
  once before the build loop (a throwaway child that only attempts the unshare)
  and prints whether isolation is **active** or **unavailable**, then threads
  the flag into `exec_build`. So behaviour is explicit, never silent.

Only `unshare`'s syscall number is arch-varying (x86_64 272 / aarch64 97, local
`#ifdef`); `CLONE_*`, `setsid`, `kill`, `waitpid`, and the poll-based sleep are
shared. No new dependency is vendored (agnosys ships namespace/Landlock/seccomp
helpers and is the likely home for the *later* bites, but pulling it now for one
`unshare` would be unjustified weight).

## Consequences

- `build --execute` builds are **hermetic** where unprivileged user namespaces
  are available, and **time-bounded** everywhere. **Verified live**: a build
  step saw only `lo` via the per-netns `/proc/net/dev` (host has 3 interfaces),
  files it created were owned by the real uid (1000, not `nobody` — the identity
  map works), and a `sleep 30` step under a 300 ms ceiling was killed and
  reported `0 - 2`.
- Tests (819, was 814): hermetic exit-code passthrough, the timeout sentinel,
  empty-argv spawn error, and the availability probe returning a clean boolean.
  The integration harness adds a tolerant netns case (asserts 1 interface when
  isolation is active; otherwise just that the build ran).
- **Best-effort isolation, not a hard gate.** On kernels without unprivileged
  userns (some hardened distros), builds still run — un-isolated but bounded —
  and the CLI says so. A future `--require-sandbox` could make it fail-closed.
- **Methodology note for verifiers**: `/sys/class/net` is mount-tied (shows the
  netns where sysfs was mounted) and is *not* a valid isolation probe;
  `/proc/net/dev` is per-netns and is.

## Scope / non-goals (this bite)

- **No filesystem confinement** yet — a step can still read/write outside
  DESTDIR (it runs unprivileged, so it can't touch root-owned paths, but it
  isn't *confined*). Landlock is the next bite.
- **No seccomp** syscall filtering yet.
- **No PID/mount namespace** beyond what network isolation needs; no per-recipe
  timeout override (fixed 1 h ceiling). All tracked on the roadmap.
- This remains hermeticity + liveness hardening, **not** a containment boundary
  against malicious recipes — recipes are trusted (curated, sha-pinned sources).

## Alternatives considered

- **Vendor `agnosys` and use `security_create_namespace`** — deferred; it pulls
  a large module + its `Result` surface for a single `unshare` today. Reconsider
  when Landlock/seccomp bites need its helpers.
- **`rlimit`/`setrlimit` for the timeout** — no wrapper in the vendored lib, and
  an rlimit (CPU time) doesn't catch a process *blocked* on I/O; the wall-clock
  `waitpid`+`SIGKILL` loop does, and reuses a tested stdlib pattern.
- **Fail-closed when userns is unavailable** — rejected as the default (would
  make takumi unusable on hardened kernels); exposed transparently instead, with
  a future opt-in flag.

## Amendment (0.11.3, audit SEC-04 / SEC-08 / SEC-10 / SEC-11)

Hardening from the pre-v1 audit: a userns uid/gid-map write failure (process
mapped to `nobody`) now **aborts the step** rather than running degraded
(SEC-04); sandbox-setup failures **warn to stderr** and `--require-sandbox`
makes them **fail-closed** (SEC-08); the timeout poll sleep is **arch-correct**
(`ppoll` on aarch64, SEC-10). Known residual (SEC-11): a step that double-forks /
`setsid`s escapes the process-group timeout kill — a PID namespace would close it
(deferred; trusted-recipe residual).
