# takumi — Pre-v1 Security Audit (2026)

- **Status**: COMPLETE — review (0.11.1) + **all remediation landed (0.11.2–0.11.5)**
- **Date**: 2026-06-17 (review 0.11.1; remediation through 0.11.5)
- **Scope version**: 0.11.0 (remediated through 0.11.5)
- **Auditor**: internal review (per CLAUDE.md P(-1) / v1.0 criterion 7)
- **Result**: 22 findings — 2 critical, 3 high, 6 medium, 6 low, 5 info.
  **Every critical/high/medium/low is fixed** (SEC-11 documented as an accepted
  trusted-recipe residual); the 5 info items are confirmed-solid or optional.
  No critical/high accepted as residual. v1.0 criterion 7 is met.

> This is the pre-v1 security audit required by v1.0 criterion 7. It reviews the
> whole build pipeline against takumi's threat model, records findings with
> severity + disposition, and states the residual risk accepted for 1.0. Fixes
> land in subsequent 0.11.x releases (see the remediation table).

## 1. Scope

The full pipeline, stage by stage:

```
recipe parse/validate → fetch (HTTPS) → verify (sha256) → extract (tar) →
patch → build (sandboxed shell) → package (.ark, signed)
```

Modules reviewed: `src/parse.cyr`, `src/validate.cyr`, `src/recipe.cyr`,
`src/fetch.cyr`, `src/source.cyr`, `src/build.cyr`, `src/sandbox.cyr`,
`src/package.cyr`, `src/ark_format.cyr`, and the CLI driver in `src/cli.cyr`.

Out of scope: the Cyrius toolchain + vendored stdlib (`lib/`, audited upstream;
takumi pins a released tag); `ark`'s installer (separate repo, consumes the
`.ark` format); the operator's host hardening.

## 2. Methodology

- Per-stage manual review against the threat model below, focused on: untrusted
  input parsing (integer/bounds/overflow), path traversal, decompression
  amplification, the integrity gates (sha256 verify-before-use, ed25519
  signing), the network trust path (TLS, redirects), and the sandbox's stated
  guarantees vs. its actual enforcement (fail-open semantics).
- Findings verified against the exact code (cited `file:line`), not inferred.
- External comparison to established source-based builders (§5).

## 3. Threat model

**Assets**: the integrity + authenticity of produced `.ark` packages; the
build host (must not be compromised or escaped by a build); reproducibility.

**Trusted**:
- **Recipes** — curated, reviewed, version-controlled (zugot). Build steps are
  arbitrary shell **by design**; recipe-authored command execution is *not* a
  vulnerability. Recipe authors are trusted.
- The Cyrius toolchain + pinned stdlib.

**Untrusted / adversarial-capable**:
- **Source tarball bytes** — even though pinned by sha256, the pin fixes *which*
  bytes, not that they are benign. A recipe author could pin a hash whose
  upstream tarball is crafted to attack the **parser** (tar/PAX/GNU headers,
  decompressors). So extraction must treat tarball bytes as hostile input.
- **The network** — DNS/transport between takumi and the source server; a
  compromised mirror or MITM. Mitigated by TLS + the sha256 gate.
- **A produced `.ark` consumed by `ark`** — the reader must be robust to a
  malformed/hostile package.

**Explicitly NOT a goal (residual, accepted)**:
- Containing a **malicious recipe**. The build is unprivileged + DESTDIR-only +
  sandboxed (netns + Landlock + timeout), but this is hermeticity/liveness
  hardening, not a security boundary against a recipe that *wants* to misbehave.
  Defense-in-depth, not a jail. Operators run builds as a throwaway unprivileged
  user.

**Privilege boundary**: takumi runs unprivileged and never writes outside its
build root / DESTDIR. The privilege boundary (installing to `/`) lives downstream
in `ark`/`shakti`, out of scope here.

## 4. Findings

22 findings: **2 critical, 3 high, 6 medium, 6 low, 5 informational**. Every
finding was verified against the cited `file:line` before inclusion. Severity is
calibrated to the threat model — a weakness reachable only by a trusted recipe
author rates lower than one reachable by **adversarial tarball bytes** (which a
sha-pin does not vouch for), **the network**, or an **untrusted `.ark`** in the
consumer.

| ID | Area | Title | Severity | Disposition |
|----|------|-------|----------|-------------|
| SEC-01 | extract | PAX `size=` decimal overflow → bounds bypass → OOB heap read into output file | **CRITICAL** | **Fixed ✅ 0.11.2** |
| SEC-02 | sign | Packages produced **unsigned** (`signing_seed = 0`) — no authenticity | **CRITICAL** | **Fixed ✅ 0.11.5** |
| SEC-03 | extract | PAX record-length overflow → negative index → OOB heap-underflow read (DoS) | HIGH | **Fixed ✅ 0.11.2** |
| SEC-04 | sandbox | userns uid/gid-map write failures ignored → silent `nobody` ownership / half-sandbox | HIGH | **Fixed ✅ 0.11.3** |
| SEC-05 | format | `.ark` reader trusts length/offset fields unbounded → OOB/OOM in the consumer | HIGH | **Fixed ✅ 0.11.4** |
| SEC-06 | fetch | `http://` accepted by the validator — contradicts the https-only invariant | MEDIUM | **Fixed ✅ 0.11.2** |
| SEC-07 | validate | Malformed source `sha256` is a warning, not an error (builds late-fails) | MEDIUM | **Fixed ✅ 0.11.2** |
| SEC-08 | sandbox | Landlock per-step apply failure is fail-open + unreported | MEDIUM | **Fixed ✅ 0.11.3** |
| SEC-09 | sandbox | Landlock grants RW to **all** of `/tmp` (not the build root) + hidden `/tmp` coupling | MEDIUM | **Fixed ✅ 0.11.3** |
| SEC-10 | sandbox | Poll sleep `syscall(7,…)` is not `poll` on aarch64 → busy-spin / wrong timeout | MEDIUM | **Fixed ✅ 0.11.3** |
| SEC-11 | sandbox | Timeout escapable by a double-fork/`setsid` step (no PID namespace) | MEDIUM | **Documented ✅ 0.11.3** (PID ns deferred; trusted-recipe residual) |
| SEC-12 | fetch | GitHub `browser_download_url` not re-validated (scheme/host) before fetch | LOW | **Fixed ✅ 0.11.2** |
| SEC-13 | fetch | Streaming download has no byte cap → disk-exhaustion DoS (bounded only by timeout) | LOW | **Fixed ✅ 0.11.2** |
| SEC-14 | extract | `SRC_MAX_BYTES` (512 MiB) > allocator `ALLOC_MAX` (256 MiB) — cap is a lie, misleading error | LOW | **Fixed ✅ 0.11.2** |
| SEC-15 | sandbox | `/dev` granted full RW incl. device/socket/FIFO creation (only `/dev/null`-class needed) | LOW | **Fixed ✅ 0.11.3** |
| SEC-16 | format | `.ark` reader: manifest ints (`release`/`size_installed`/`build_date`) unvalidated on read | LOW | **Fixed ✅ 0.11.4** |
| SEC-17 | extract | Regular-file writes lack `O_NOFOLLOW` (write-through in-tree symlink) — contained by lexical guard | INFO | Optional hardening |
| SEC-18 | extract | gzip `ISIZE` reflects only the last member of a multi-member stream — fail-closed correctness limit | INFO | Optional (correctness) |
| SEC-19 | build | Shell single-quoting (`_sh_squote`) — verified breakout-proof | INFO | No change (solid) |
| SEC-20 | sandbox | `exec_vec_sandboxed` argv/envp + fork/exec/wait + fd hygiene — verified correct | INFO | No change (solid) |
| SEC-21 | fetch | Write-vs-transport error classification — a truncated/0-byte file cannot pass verification | INFO | No change (safe) |
| SEC-22 | extract | Octal `size`/mode/mtime fields are bounded + positive; setuid/setgid/sticky stripped | INFO | No change (solid) |

### Detailed findings (verified)

**SEC-01 — PAX `size=` overflow → OOB heap read into the output file (CRITICAL).**
`src/source.cyr` `_pax_decimal` accumulates `v = v*10 + digit` with **no overflow
guard**; a PAX `x` header `size=<19-20 digits>` yields a large positive `sv`
stored as the size override. At the write site, the bound `if (pos + esize >
tar_len)` overflows i64 to negative → check passes → `file_write_all(ffull,
tar_buf + pos, esize)` streams up to ~8 EiB from the heap into the output file
(adjacent-heap disclosure) or faults (DoS). **Reachable from a sha-matching but
adversarial tarball.** Fix: overflow-guard `_pax_decimal`; independently reject
`esize < 0` and use a non-overflowing bound (`esize > tar_len - pos`).

**SEC-02 — packages produced unsigned (CRITICAL).** `src/cli.cyr:253` calls
`ark_write(…, 0)`; `ark_format.cyr:328` `if (signing_seed != 0) signed = 1` →
the unsigned branch: no `ARK_FLAG_SIGNED`, no pubkey/signature. Every `.ark`
takumi ships has integrity (sha256 root) but **zero authenticity**, contradicting
the trust model. The ed25519 machinery works (tested with a real seed) but the
pipeline never supplies one — there is no key-loading/flag/config. Fix: thread a
32-byte signing seed from a maintainer key (`--signing-key <path>` / pinned
config), validate length, pass to `ark_write`; fail-closed or loudly warn when
absent. Needs a small key-management design (own release / ADR).

**SEC-03 — PAX record-length overflow → OOB read (HIGH).** `_pax_parse`: `rlen
= rlen*10 + digit` unguarded; a 20-digit length prefix makes `rec_end = ds +
rlen` negative, the `rec_end > len` guard passes, `i = rec_end` goes negative,
and the next `load8(data + i)` reads before the buffer → SIGSEGV/DoS. Reachable
from an adversarial tarball. Fix: overflow-guard `rlen`; add `if (rec_end < i)
break`.

**SEC-04 — userns map-write failures ignored (HIGH).** `_sandbox_apply_netns`
checks `unshare` but discards the return of all three `/proc/self/{setgroups,
uid_map,gid_map}` writes and returns success regardless. If `unshare` succeeds
but a map write fails, the build runs mapped to the overflow id (`nobody`) and
silently mis-owns every DESTDIR file — violating the module's own stated
guarantee. Fix: on any map-write failure after a successful `unshare`, fail the
step (or signal the parent), never proceed silently.

**SEC-05 — `.ark` reader trusts length/offset fields (HIGH).** `ark_read`
parses manifest/index/data via `_get_u32`/`_get_u64` with no check that the
declared lengths/counts fit within the buffer: `str_new(buf+off, mlen)`,
`alloc(u_len)` (up to 2^64), `memcpy(path, buf+off, plen)`, and an index loop
over an in-band `count` — a malformed/hostile `.ark` (untrusted in the ark
consumer) causes OOB reads, OOM-sized allocs, or `memcpy` past the buffer. The
root-hash check doesn't protect parsing that reads beyond the hashed region. Fix:
checked `_get_*` that take the buffer length; validate `off + field_len <= r`
before every `str_new`/`memcpy`/`alloc`; bound `count`; reject oversized
`u_len`/`c_len`.

**SEC-06 — `http://` accepted (MEDIUM).** `validate.cyr` `url_has_valid_scheme`
returns 1 for `http://` as well as `https://`, contradicting the documented
https-only invariant. The sha gate preserves integrity, so this is a
confidentiality/policy break, not a tampering vector. Fix: accept only
`https://`.

**SEC-07 — malformed sha256 is a warning (MEDIUM).** `_validate_source_sha`
pushes a warning (not an error) for a non-64-hex digest, so the recipe builds and
fails late at the fetch gate with a generic mismatch. Fix: promote a non-empty
malformed hash to a hard error (keep empty as the existing error).

**SEC-08 — Landlock apply failure fail-open + unreported (MEDIUM).**
`_sandbox_apply_landlock` fails closed *internally* (never installs a half
policy — good), but the caller discards its return; if confinement can't be
applied after the once-per-build probe, the step runs unconfined with no signal
in the log/result. Fix: surface the per-step apply result (child sentinel exit)
and warn or fail.

**SEC-09 — Landlock grants all of `/tmp` (MEDIUM).** The RW rule covers the
entire `/tmp` tree, not the build root, so a step can write other builds' trees,
sockets, lockfiles, etc.; and confinement is silently coupled to the build root
living under `/tmp` (a non-`/tmp` `build_root` would deny all writes). Fix: grant
RW on the actual build-root path passed from `build.cyr` + a narrow `/dev`
allowance, not blanket `/tmp`.

**SEC-10 — poll sleep wrong on aarch64 (MEDIUM).** The timeout loop sleeps via
`syscall(7,…)` (= `poll` on x86_64 only); aarch64 has no `poll` (only `ppoll`),
so the call errors/returns without sleeping → busy-spin and a wildly wrong
wall-clock timeout. `unshare` is already arch-`#ifdef`'d here; the sleep is not.
Fix: per-arch sleep (`ppoll`/`SYS_PPOLL` on aarch64) behind the same `#ifdef`.

**SEC-11 — timeout escapable without a PID namespace (MEDIUM).** `setsid` +
`kill(-pid)` group-kills the step, but a step that `setsid`s/double-forks escapes
into another group and survives the timeout (and outlives its netns). Inherent
without `CLONE_NEWPID`. Disposition: add a PID namespace (audit-warranted sandbox
extra, 0.11.3) or document that the timeout doesn't bound double-forked daemons.

**SEC-12/13/14/15/16** (LOW) — re-validate the resolved GitHub URL scheme;
cap the streaming download size (e.g. to `SRC_MAX_BYTES`); reconcile
`SRC_MAX_BYTES` with the allocator cap (or null-check `alloc`); narrow `/dev` to
read/write (drop make-node rights); range-validate manifest ints on `.ark` read.

**SEC-17…22** (INFO) — confirmed-solid or contained; see the table. Notably the
shell quoting, the fork/exec hygiene, the path-traversal + symlink lexical
guards, the setuid/setgid/sticky stripping, and the sha256 verify-before-extract
gate are all sound.

## 5. External comparison (domain completeness)

How takumi's hardening compares to established source-based builders:

| Control | takumi | Arch `makepkg` | Gentoo `ebuild` | Nix | Debian `sbuild` |
|---|---|---|---|---|---|
| Source integrity pin | sha256, hard gate pre-extract | sha256/b2 in `.SRCINFO` | Manifest hashes | fixed-output hash | per-`.dsc` checksums |
| Network during build | **cut (netns)** | not cut by default | sandbox blocks net | **no network** (fixed-output) | cut in some setups |
| FS confinement | **Landlock** (writes→/tmp+/dev) | `fakeroot` only | sandbox (bind/`LD_PRELOAD`) | chroot/bwrap | schroot/overlay |
| Wall-clock timeout | **yes** (per step) | no | no | builder timeout | no |
| Reproducible output | yes (`SOURCE_DATE_EPOCH`) | partial | partial | **yes** (core goal) | partial |
| Artifact signing | ed25519 (see findings) | optional (`gpg`) | optional | store path = hash | `debsign` (gpg) |
| Runs unprivileged | **yes** | yes | yes (sandbox user) | yes (build users) | yes |

Observations: takumi's network-cut + Landlock + per-step timeout put it ahead of
`makepkg`/`ebuild` on build-step hardening and on par with bwrap/chroot
approaches for the hermeticity it claims; reproducibility matches the field via
`SOURCE_DATE_EPOCH`. Signing-key management (§4) is the area to get right for
authenticity parity.

## 6. Residual risk statement

After remediation (§7), the **accepted** residual risk for 1.0 is:

- **Malicious recipes are out of scope** (by design). The build runs unprivileged
  + DESTDIR-only + sandboxed, but a hostile recipe can do anything the build uid
  can outside the confined paths (read `/`, use IPC the netns doesn't cut,
  write within the build root). Operators MUST run builds as a throwaway
  unprivileged user over curated, reviewed recipes. The sandbox is
  defense-in-depth, **not** a jail.
- **No seccomp** (syscall filtering) in 1.0 — the audit deems it a post-1.0
  enhancement; the netns + Landlock + timeout + unprivileged-uid posture is the
  v1 bar, with `--require-sandbox` (SEC-08 fix) for operators who need fail-closed
  isolation.
- **Tarball-bytes are adversarial-input** to the parser: the SEC-01/03 fixes
  close the known memory-safety holes; the parser remains hand-written C-style
  code and should keep getting fuzz/bounds attention (a fuzz harness is blocked
  on a Cyrius AFL/libFuzzer equivalent — tracked).
- The privilege boundary for installation (writing to `/`) is downstream in
  `ark`/`shakti`, not takumi.

No CRITICAL or HIGH finding is accepted as residual — all are scheduled for
remediation before 1.0 (§7).

## 7. Remediation plan

Findings are clustered into bounded 0.11.x releases by area + severity. The two
CRITICALs lead.

- **0.11.2 — input hardening — DONE ✅**: SEC-01 + SEC-03 (PAX decimal/record
  overflow guards + overflow-safe write bound — the memory-safety CRITICAL/HIGH),
  SEC-06 (https-only with a loopback `http` carve-out), SEC-07 (malformed-sha →
  error), SEC-12 (re-validate the resolved GitHub URL), SEC-13 (streaming size
  cap via a counting sink, `FETCH_MAX_ARTIFACT` 256 MiB), SEC-14 (`SRC_MAX_BYTES`
  = allocator ceiling + null-checked allocs). Regression tests added for the PAX
  overflows + the scheme/sha policy; full suite + integration green.
- **0.11.3 — sandbox hardening — DONE ✅**: SEC-04 (userns map-write failure now
  aborts the step — no silent `nobody` ownership), SEC-08 (sandbox-setup failures
  warn to stderr + `--require-sandbox` fail-closed mode), SEC-09 (Landlock
  confines to the **build root**, not all `/tmp`; `TMPDIR` redirected inside it),
  SEC-10 (arch-correct sleep — `ppoll` on aarch64), SEC-15 (`/dev` narrowed to
  read/write existing nodes). SEC-11 (timeout escape via double-fork) is
  **documented** as a trusted-recipe residual — a PID namespace would close it
  but needs a double-fork PID-1 reaper; deferred. seccomp deferred post-1.0.
  Verified live: build-root confinement blocks an out-of-root `/tmp` write while
  a real gcc compile still succeeds (TMPDIR redirect).
- **0.11.4 — `.ark` reader robustness — DONE ✅**: SEC-05 (every manifest/index/
  data length + offset validated against the verified content region `[0, r)`
  before any `str_new`/`memcpy`/`alloc`, via `_ark_in`; `u_len` capped at
  `ARK_MAX_DATA` (256 MiB) + null-checked allocs → no OOB read / decompression-
  bomb OOM in the consumer), SEC-16 (manifest ints clamped non-negative on
  read). Regression test: a hash-valid but oversized-manifest-length `.ark` is
  rejected (0), not OOB-read.
- **0.11.5 — package signing / key management — DONE ✅**: SEC-02 —
  `--signing-key <path>` (64-hex ed25519 seed) threaded into `ark_write`;
  fail-closed on a bad key, loud UNSIGNED warning when absent. Signed `.ark`s
  verify on read. [ADR 0014](../adr/0014-package-signing-key.md).
- INFO items (SEC-17/18) optional; SEC-19…22 require no change.
- **1.0.0** — all CRITICAL/HIGH/MEDIUM/LOW findings resolved (SEC-11 documented
  residual); ready to tag.

**Remediation complete (0.11.5).** All 16 actionable findings are fixed; SEC-11
is an accepted documented residual; the 5 INFO items need no change.

This sequence supersedes the earlier "0.11.x remediation (TBD clusters)" note in
the roadmap's Path-to-1.0.
