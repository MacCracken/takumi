# 0002 — Source extraction safety (tar/tar.gz)

- **Status**: accepted (takumi 0.8.3); amended 0.8.5 — `.tar.xz`/`.tar.bz2` now supported
- **Date**: 2026-06-16 (amended 2026-06-17)

> **0.8.5 amendment**: the "no xz/bzip2 codec" limitation below is resolved.
> stdlib `sankoch` 2.4.x (cyrius 6.2.16) ships xz/bzip2 decode, so
> `extract_archive` now sniffs and decodes `.tar.xz` (magic `FD 37 7A 58 5A 00`)
> and `.tar.bz2` (`BZh`) in addition to `.tar`/`.tar.gz`. xz/bz2 lack a
> gzip-style ISIZE trailer, so the output buffer is grown on a
> buffer-too-small return (capped at 512 MiB) rather than pre-sized. All other
> decisions below (typeflag allow-list, path-traversal guard, fail-closed
> policy) are unchanged and apply identically to the new envelopes.

## Context

Building a recipe means unpacking an upstream source archive into a scratch
directory before configure/make/install run. Archive extraction is a classic
attacker-controlled sink: a malicious or malformed tarball can escape the
destination via `../` components, absolute paths, or symlinks whose targets
point outside the tree ("tar-slip" / "zip-slip"). takumi pulls extraction into
the 0.8.x arc (0.8.3) to settle this surface before the pre-v1 security audit;
network download and build execution stay in 0.9.x.

The stdlib provides DEFLATE/gzip via `sankoch` (`gzip_decompress`,
`gzip_compress`) but **no xz/lzma or bzip2 codec**, so the supported set is
`.tar` and `.tar.gz`/`.tgz` only.

## Decision

`extract_archive(archive_path, dest_dir)` in `src/source.cyr`, with a
**fail-closed** guard model — any unsupported entry or unsafe path aborts the
whole extraction before a single offending byte is written.

1. **Format**: sniff by magic (gzip `1f 8b`, else require `ustar` at offset
   257; an empty archive is just zero blocks). gzip output is sized from the
   trailer ISIZE and capped at 512 MiB; `.tar.xz`/`.tar.bz2` fail the magic
   check by design (no codec).
2. **ustar parse**: 512-byte headers, octal size field, header checksum
   validated on every header, `prefix`+`name` joining, two-zero-block
   terminator.
3. **Typeflag allow-list** (fail-closed): only regular (`0`/NUL), directory
   (`5`), symlink (`2`). Hardlinks, devices, and GNU/pax extension records
   (`L`/`K`/`x`/`g`) return `SRC_ERR_UNSUPPORTED` and abort — we never
   skip-and-continue, because a skipped long-name/extended header would desync
   the following entry's name. (Consequence: pax/GNU-long-name archives are
   rejected rather than mis-extracted; broader format support is a follow-up.)
4. **Path guard** (the security core), applied before any filesystem write:
   - Entry paths: reject empty, absolute (leading `/`), **any `..` component**,
     empty interior components (`a//b`), and NUL/control/backslash bytes. A
     literal `..` is never legitimate in a canonical archive entry, so
     rejecting it outright removes a class of normalization-bug risk.
   - Symlink targets: reject absolute targets and bad bytes, then resolve the
     target against the link's own directory depth — if the running depth ever
     drops below 0 the link escapes the root, so reject. **Relative targets
     that stay within the root are allowed** (autotools/libtool ship them).
     The check is purely lexical; the extractor writes the literal target via
     `sys_symlink` and never *follows* a link, so it cannot be tricked into
     writing outside `dest`.
5. **Errors**: a `SrcErr` enum (`OPEN`/`TOO_LARGE`/`BAD_MAGIC`/`GUNZIP`/
   `TRUNCATED`/`BAD_HEADER`/`UNSUPPORTED`/`UNSAFE_PATH`/`WRITE`); the function
   returns `0 - SRC_ERR_*`.

Source integrity is verified separately by `verify_source_hash(path,
expected_sha256)` — streamed SHA-256 compared to the recipe's `source.sha256`
— intended to run **before** extraction.

## Consequences

- **Bounded, hermetic tests**: the conformance suite builds ustar archives by
  hand in memory (no shell), covering positives (regular/dir/symlink, empty
  file, multi-block file, prefix+name, `.tar.gz`, empty archive) and the
  malicious set (`../escape`, `a/../b`, `/etc/x`, absolute/escaping symlink
  targets, unsupported typeflags, bad checksum, truncated, bad magic), each
  asserting the specific `SRC_ERR_*` and that no out-of-root artifact appears.
- **Whole-archive-in-memory**: the archive and gunzip output are buffered (512
  MiB cap). Fine for normal sources; a streaming extractor is future work.
- **Format coverage is intentionally narrow**: `.tar`/`.tar.gz` only; xz/bz2
  await stdlib codecs; pax/GNU long names are rejected, not mis-handled.
- **Symlink fidelity upstream**: `create_file_list` now lstat-classifies
  symlinks (no longer follows symlinked directories), so a `.ark` built from an
  extracted tree records links faithfully (see 0.8.3 / [ADR 0001](0001-ark-binary-format.md)).

## Alternatives considered

- **Reject all symlinks** — simplest, but breaks real autotools/libtool
  tarballs. Rejected in favor of the lexical depth check.
- **Normalize-and-allow `..` in entry paths** — more permissive but relies on a
  correct normalizer; rejecting `..` outright is stricter and trivially
  auditable.
- **Skip unknown typeflags and continue** — rejected; desync risk makes it
  unsafe. Fail-closed instead.
