# 0014 — Package signing: supplying a key (closing SEC-02)

- **Status**: accepted (takumi 0.11.5)
- **Date**: 2026-06-17
- **Closes**: security audit SEC-02 (CRITICAL)
- **Builds on**: [ADR 0001](0001-ark-binary-format.md) (the `.ark` ed25519 trailer)

## Context

The `.ark` format and `ark_write` have supported ed25519 signing since 0.8.x
(deterministic key from a 32-byte seed; pubkey + signature in the trailer;
`ark_read` verifies it). But the build pipeline called `ark_write(…, 0)` — seed
`0` takes the unsigned branch — so **every package takumi actually produced was
unsigned**. Packages had integrity (SHA-256 root hash) but **no authenticity**:
anyone able to place a `.ark` where `ark` reads it could supply arbitrary
contents with a valid root hash. The audit rated this CRITICAL (it negates the
authenticity half of the trust model). The gap was purely "no key is ever
supplied" — there was no key-loading, flag, or config.

## Decision

Add a signing-key surface to `build --execute` and wire the existing machinery.

- **`--signing-key <path>`** (`src/cli.cyr`). The key file holds the ed25519
  **seed as 64 lowercase hex characters** (trailing whitespace/newline trimmed)
  — friendly to generate (`openssl rand -hex 32 > key`) and to store in text.
  `_cli_load_signing_seed` reads it, validates it is exactly 64 lowercase-hex
  (reusing `sha256_is_lowercase_hex64`), decodes to a 32-byte seed, and threads
  it through `cmd_build → _cli_build_execute → _cli_build_one → ark_write`.
- **Fail-closed on a bad key.** If `--signing-key` is given but the file is
  missing or not a valid 64-hex seed, the build **fails** (exit 1) — it does not
  silently fall back to unsigned. (You asked to sign; a broken key is an error.)
- **Loud, never silent, when no key is given.** Without `--signing-key`, the
  build prints `WARNING: no --signing-key; produced packages will be UNSIGNED`
  and produces an unsigned `.ark`. This keeps the dev/local flow working while
  ensuring the unsigned state is never silent (the audit's minimum bar).

The hex-seed-in-a-file is intentionally simple key *handling*, not key
*management*: takumi consumes a seed; generating, storing, rotating, and
protecting the maintainer key are the operator's/release-infra's job.

## Consequences

- `build --execute --signing-key <key>` produces **signed** `.ark`s that
  `ark_read` (and ark) verify (root hash + ed25519 over it + per-file hashes).
  **Verified**: a build with a key yields `apk_signature != 0` and the
  `ARK_FLAG_SIGNED` header bit set; a build without a key yields an unsigned
  package + the warning; a malformed `--signing-key` fails the build.
- Tests (+13, 884 total): `_cli_load_signing_seed` (missing / short / non-hex →
  0; valid hex64 → 32-byte seed), and end-to-end signed vs unsigned vs
  bad-key-fails via `cmd_build`.
- The build timestamp is still `SOURCE_DATE_EPOCH`-reproducible; signing is
  deterministic from the seed, so a signed build is reproducible too (same
  recipe + sources + epoch + key → byte-identical signed `.ark`).

## Alternatives considered

- **Raw 32-byte binary key file** — rejected; hex-in-text is easier to generate,
  inspect, and store, and avoids binary-file handling pitfalls.
- **Embed/auto-generate a key** — rejected; a built-in or derived key is a known
  (public) key = no real authenticity (the very thing SEC-02 is about).
- **Refuse to build without a key (hard fail by default)** — rejected as the
  default (breaks local/dev builds); the loud warning meets the audit bar, and an
  operator who wants hard enforcement can treat the warning as a gate. A
  `--require-signing` flag can be added later if a consumer needs it.

## Follow-ups

- Optional `--require-signing` (fail-closed when no key), mirroring
  `--require-sandbox`, if a release pipeline wants it enforced.
- Key management proper (rotation, hardware-backed keys) is out of scope —
  downstream of takumi.
