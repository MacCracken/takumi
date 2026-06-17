# 0009 — PAX extended header support (typeflag `x` / `g`)

- **Status**: accepted (takumi 0.9.6)
- **Date**: 2026-06-17
- **Amends**: [ADR 0002](0002-source-extraction-safety.md) (source extraction safety),
  builds on [ADR 0008](0008-v7-tar-checksum-gated-headers.md) (v7 / checksum gate)

## Context

After v7 support (0.9.5), `extract_archive` handled `ustar` and `v7`, but still
aborted with `SRC_ERR_UNSUPPORTED` on any header whose typeflag wasn't
regular/dir/symlink. A survey of real upstream tarballs showed this rejects
major packages:

| tarball            | format | extended headers | takumi before 0.9.6 |
|--------------------|--------|------------------|---------------------|
| GNU hello / sed    | v7     | none             | ok (0.9.5)          |
| GNU tar / gettext  | ustar  | none             | ok                  |
| **OpenSSL 3.3.0**  | ustar  | PAX `g` (global) | **fail (`-7`)**     |
| **CPython 3.12.3** | ustar  | PAX `x` (per-file), path = 108 B | **fail (`-7`)** |

PAX (POSIX.1-2001) extended headers are emitted by modern `tar` whenever an
attribute doesn't fit the `ustar` header — most commonly a **path longer than
100 bytes** (the `ustar` name limit; `prefix` extends it to 255 but long single
components still overflow), and a **global header** that `tar --format=pax`
always prepends. So a package builder that fetches arbitrary upstreams must
parse them. (GNU long-name `L`/`K` headers appeared in *none* of the sampled
tarballs, so they remain deferred — wait for a real instance.)

## Decision

Parse PAX extended headers and apply their overrides to the entry they govern;
do not treat them as filesystem entries.

A PAX header's data block is a sequence of records:

```
"<len> <key>=<value>\n"
```

where `<len>` is the decimal byte length of the whole record (including its own
digits). `extract_archive` (`src/source.cyr`) now:

- **Intercepts typeflag `x` (120, per-file) and `g` (103, global)** before the
  regular/dir/symlink dispatch. It parses the record data (`_pax_parse`) into a
  24-byte override record — `path`, `linkpath`, `size` — ignoring every other
  key (`mtime`, `uid`, `comment`, …), then consumes the data block without
  emitting anything.
- **Applies overrides to the next real entry**, precedence **per-file (`x`) >
  global (`g`) > the `ustar`/`v7` header**:
  - `path` → the entry's extraction path (so the 108-byte CPython path is
    reconstructed exactly);
  - `linkpath` → a symlink's target;
  - `size` → the data length (the `ustar` octal `size` is `0` / overflowed for
    files > 8 GiB).
- **Resets the per-file (`x`) record after each real entry** (it governs exactly
  the following entry); the global (`g`) record persists for the rest of the
  archive.

**Security: the PAX `path`/`linkpath` overrides flow through the *same*
`_tar_path_is_safe` / `_symlink_target_is_safe` guards as the header fields.** A
malicious PAX `path=../escape` is rejected with `SRC_ERR_UNSAFE_PATH` — proven
by a dedicated test. PAX does not widen the trust surface; it only changes where
the path string comes from, and that string is guarded identically.

## Consequences

- takumi extracts `ustar` (with/without PAX), `v7`, and PAX tarballs across
  gz/xz/bz2. **Verified live**: OpenSSL 3.3.0 (`g`) and CPython 3.12.3 (`x`,
  108-byte path) now extract **byte-identically to system `tar`** — full
  recursive content diff is clean, and the long-path file is byte-for-byte
  correct.
- Tests (814 total, was 795): a PAX fixture builder (`_tb_pax_record` with
  self-referential length framing, `_tb_emit_pax`) drives path override (long
  name beats the `ustar` placeholder), global-header tolerance, size override
  (`ustar` size 0 → PAX size 5), linkpath override, and the traversal-guard
  rejection. The integration harness adds a real `tar --format=pax` loopback
  build over a > 100-byte path.
- Unknown typeflags other than `x`/`g` (GNU `L`/`K`, hardlink, char/block/fifo)
  still abort with `SRC_ERR_UNSUPPORTED` — unchanged, fail-closed.

## Alternatives considered

- **Keep rejecting PAX** — rejected; it excludes OpenSSL, CPython, and most
  modern `tar --format=pax` output.
- **Honour only `path` / skip `g` blindly** — rejected as incomplete; `linkpath`
  and `size` matter for symlinks and large files, and a parsed (not blindly
  skipped) global header is needed to apply its records correctly.
- **Shell out to `tar`** — rejected (external dependency + trust/sandbox surface
  for what is a pure in-process step today).
- **Support GNU `L`/`K` in the same release** — deferred; no sampled tarball used
  them, and their data format differs (raw name, not records). Add on first real
  instance.

## Follow-ups

- GNU long-name/long-link (`L` = 76, `K` = 75) extended headers — deferred until
  a recipe needs them.
