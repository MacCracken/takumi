# 0008 — v7 tar support: checksum-gated headers (not `ustar` magic)

- **Status**: accepted (takumi 0.9.5)
- **Date**: 2026-06-17
- **Amends**: [ADR 0002](0002-source-extraction-safety.md) (source extraction safety)

## Context

`extract_archive` (ADR 0002) hard-required the `ustar` magic string at byte
offset 257 of every header block — both as the initial "is this a tar?" sniff
and as a per-block gate. Real-world tarballs broke this assumption: **GNU
release tarballs are distributed in the pre-POSIX *v7* tar format**, which
predates the `ustar` magic field and leaves offset 257 zero. Concretely, GNU
hello 2.12.1 (`hello-2.12.1.tar.gz`) is v7 — confirmed live, the bytes at 257
are NUL — so takumi rejected it with `SRC_ERR_BAD_MAGIC` before any verify /
patch / build could run. This was surfaced while confirming patch application
(0.9.4) against a real project.

The `ustar` magic was never a security control. The real integrity gates are:
1. the **header checksum** (offset 148, octal sum of all 512 bytes with the
   checksum field counted as spaces) — a strong "this is a genuine tar header"
   signal that *predates* and is independent of the magic;
2. the **path-traversal guard** (`_tar_path_is_safe`, rejecting `..`, absolute
   paths, bad bytes); and
3. the **typeflag whitelist** (regular / dir / symlink only).

v7 is a strict field *prefix* of ustar — name, mode, size, checksum, typeflag,
and linkname live at the same offsets; ustar only *adds* magic/version/uname/
gname/dev/prefix above offset 257. So a v7 header passes the checksum, path,
and typeflag gates identically; only the magic assertion stood in the way.

## Decision

**Gate header acceptance on the checksum, not the `ustar` magic.**

- **Initial sniff** (`src/source.cyr`): a non-zero first block is accepted iff
  `_tar_checksum_ok(block)` — replacing the `memeq(block+257,"ustar",5)` check.
  (`SRC_ERR_BAD_MAGIC` is retained as the error name for "first block isn't a
  valid tar header".)
- **Per-block loop**: drop the `ustar`-magic assertion; the checksum
  (`_tar_checksum_ok`, already computed) is the sole header-validity gate.
- **Pure-v7 directories**: v7 has no directory typeflag — directories are
  regular entries (`typeflag` `0`/NUL) whose name ends in `/`. After computing
  the entry path, a regular entry with a trailing-slash name is reclassified as
  a directory (so it is `mkdir`'d, not written as a zero-byte file). Old-GNU
  tarballs that *do* use the `5` dir typeflag (e.g. GNU hello) were already
  handled.

`ustar` tarballs are unaffected (their checksum is valid too); the magic is now
simply ignored rather than required.

## Consequences

- takumi extracts both POSIX `ustar` and pre-POSIX `v7` tarballs. Real GNU
  release tarballs (and any other v7 producer) now flow through the full
  pipeline. **Verified live** against the real `hello-2.12.1.tar.gz` (v7, no
  magic): fetch → verify (sha256) → extract → patch (`patching file
  src/hello.c`) → build → package.
- **No security regression.** The checksum is a stronger header validator than
  a fixed magic string; a 512-byte block of arbitrary bytes fails the checksum
  and is still rejected (`SRC_ERR_BAD_MAGIC`) — covered by a new test. The
  path-traversal guard and typeflag whitelist are unchanged.
- Tests: an in-memory v7 fixture builder (`_tb_finalize_v7` / `_tb_emit_file_v7`
  — checksum-valid, magic-less) drives three new groups: a v7 archive (`5`-dir
  + nested file + top-level file) extracts; a pure-v7 directory (regular
  typeflag, trailing slash) is created as a directory; and a 512-byte non-tar
  block is rejected by the checksum gate. 795 tests (was 782).

## Alternatives considered

- **Keep requiring `ustar`; reject v7** — rejected. It excludes a large class of
  real upstream tarballs (every GNU release) for no security benefit.
- **Sniff v7 by a heuristic other than the checksum** (e.g. "all-NUL at 257") —
  rejected. The checksum already exists, is exact, and validates the *whole*
  header rather than one field; heuristics are weaker and redundant.
- **Add a separate v7 code path** — rejected. v7 is a field-prefix of ustar; one
  checksum-gated path handles both with less code and no divergence.
- **Pre-convert with system `tar`** — rejected. Adds an external dependency and a
  trust/sandbox surface to a step that is pure in-process today.

## Follow-ups

- PAX (`x`/`g`) and GNU long-name (`L`/`K`) extended headers are still
  unsupported (`SRC_ERR_UNSUPPORTED`); add when a recipe needs paths > 100 bytes
  that aren't covered by the ustar `prefix` field.
