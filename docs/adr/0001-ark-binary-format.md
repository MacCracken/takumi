# 0001 — `.ark` v1 on-disk binary format

- **Status**: accepted (takumi 0.8.2)
- **Date**: 2026-06-16

## Context

takumi builds `.ark` packages from CYML recipes, and ark installs them.
Through 0.8.1 the build produced a fully-populated `ArkManifest` +
`ArkFileEntry` list **in memory** only — there was no on-disk `.ark`
format defined anywhere (not in takumi's `rust-old/` reference, not in
the Cyrius port, and ark had no reader). The on-disk format was a 0.9.x
roadmap item.

We pulled the writer into the 0.8.x arc to **settle the artifact-integrity
surface before the pre-v1 security audit** and to lighten 0.9.x. Defining
the format requires several decisions that are hard to reverse later
(it becomes the contract ark must read), so they are recorded here.

Constraints from CLAUDE.md: builds must be reproducible (same recipe +
same sources ⇒ identical `.ark`), SHA-256 integrity on produced
artifacts, and signing before v1.

## Decision

A 5-section little-endian format, version-stamped `.ark` v1
(`src/ark_format.cyr`):

```
HEADER(16B): magic 0x89 'A' 'R' 'K' | u16 version | u16 flags
             | u8 compress_algo | u8 compress_level | u8 hash_algo
             | u8 sig_algo | u32 reserved
MANIFEST:    u32 len | TOML text ([[manifest]] table)
FILE-INDEX:  u32 count | per entry: u8 type | u8 eflags | u32 path_len
             | path | u64 size | [32B sha256] | [u32 tlen | target] | u64 data_offset
DATA:        u64 uncompressed_len | u64 compressed_len | deflate stream
TRAILER:     32B root_hash | u8 has_sig | [32B pubkey | 64B signature]
```

Key choices and rationale:

1. **Manifest as embedded TOML text, parsed by stdlib `bayan`.**
   Human-inspectable, reuses the same parser the recipe pipeline uses,
   and keeps the audit surface small (no bespoke manifest binary codec).
   Manifest + file index are stored **uncompressed** so ark can read
   metadata without inflating payloads.

2. **Self-contained, symmetric escaping.** bayan delimits escaped
   basic strings correctly but does **not** un-escape, so `ark_write`
   escapes (`\`, `"`, newline, tab, CR) and `ark_read` un-escapes — we
   never depend on bayan to un-escape. Verified against bayan 2.3.1.

3. **DEFLATE at a pinned level (6) via stdlib `sankoch`.** The level is
   a constant, also recorded in the header and asserted on read.
   Compression of the data section is mandatory in v1; there is no
   silent stored-mode fallback (that would make output data-dependent).
   The `compress_algo` header byte reserves room to add zstd/LZ4 later
   without a format-version bump.

4. **Integrity anchor = SHA-256 root over the whole prefix `[0, R)`**
   (header → data block). The ed25519 signature signs the **32 raw
   root-hash bytes**, not the whole file — the root hash already commits
   the entire prefix, so this is equivalent in strength and O(1) for
   signer and verifier. The pubkey is embedded so a package is
   self-verifiable against a trust store.

5. **Deterministic signing.** ed25519 (RFC 8032) is deterministic; with
   a fixed signing seed the signature is byte-stable. Reproducible
   builds MUST supply a fixed seed/key and MUST NOT use
   `ed25519_generate_keypair` (CSPRNG).

6. **Raw bytes for hashes/keys/sig in binary fields** (32/32/64), not
   hex. Halves index size and removes hex-case ambiguity (a
   reproducibility footgun). The in-memory model keeps hex; we convert
   at the serialization boundary.

## Consequences

- **Reproducible by construction**: pinned compress level + codec
  version, sorted file index (path order) reused for both the index and
  the data concatenation, no mtimes (only the explicit `build_date`
  input), no padding, explicit little-endian encoding, values-only
  serialization. The test suite builds the same fixture twice and
  asserts byte-identical output.
- **`sankoch` and `sigil` versions are reproducibility dependencies** —
  pinned via `cyrius.lock`. A codec change could alter output bytes and
  must be treated as a format-affecting change.
- **Whole-file-in-memory**: both writer and reader buffer the full
  package (uncompressed stream + compressed buffer). Fine for normal
  packages; multi-GB trees are a known scaling limit, to be addressed by
  a future streaming-block writer.
- **ark needs a matching reader.** Until it lands, the roundtrip +
  determinism + tamper tests in `tests/takumi.tcyr` are the conformance
  harness (write → read → verify root hash, signature, and every
  per-file hash; tamper a byte → read fails).
- **Format evolution**: additive changes go behind the reserved flag
  bits / algo bytes; structural changes bump `format_version` (readers
  reject unknown versions).

## Alternatives considered

- **Packed binary manifest** — more compact but opaque and a larger
  bespoke codec to audit and keep in sync with ark. Rejected in favor of
  inspectable TOML.
- **zstd compression** — better ratio, but no stdlib codec today and
  pinning level/version for reproducibility is harder. Deferred behind
  the `compress_algo` byte.
- **Signing deferred to 0.9.x** — rejected; signing is part of the
  integrity surface we want settled before the security audit.

## Amendment (0.11.4, audit SEC-05 / SEC-16)

`ark_read` now treats a `.ark` as untrusted input (the `ark` consumer reads
packages it did not produce). Every manifest/index/data length, offset, and
count is validated against the root-hash-verified content region `[0, r)` before
any `str_new`/`memcpy`/`alloc` (`_ark_in`, overflow-safe); the declared
uncompressed data size is capped at `ARK_MAX_DATA` (256 MiB) to bound a
decompression bomb, and every allocation is null-checked. Manifest integers are
clamped non-negative. A malformed package is rejected (return 0), never an
out-of-bounds read or OOM.
