# 0004 — Recipe source model (url / github_release / local)

- **Status**: accepted (takumi 0.9.0)
- **Date**: 2026-06-17

## Context

0.9.0 added an integration harness that runs takumi's CLI over the real zugot
recipe corpus (563 recipes). It immediately showed takumi parsed only **434**:
its `SourceSpec` modeled a single shape — `[source] url = … sha256 = …` —
while zugot uses three:

| Shape | `[source]` keys | count |
|---|---|---|
| URL | `url` + `sha256` | 434 |
| GitHub release asset | `github_release = "owner/repo"` + `release_asset` + `sha256` | 108 |
| Local / meta | `local = true` (no upstream) | 20 |
| (other) | — | 1 |

The 129 non-parsing recipes were not parser bugs; they were unmodeled source
shapes. takumi must handle the whole corpus to build AGNOS.

## Decision

`SourceSpec` gains a **`kind`** tag (`SRC_KIND_URL` / `SRC_KIND_GITHUB` /
`SRC_KIND_LOCAL`) plus `github_release`/`release_asset` fields
(`src/recipe.cyr`). The legacy `src_new(url, sha256, patches)` is unchanged and
sets `kind = URL` (a zero-init alloc already reads as URL), so existing callers
and tests are untouched; `src_new_github(...)` and `src_new_local(...)` are
added.

- **Parser** (`_parse_source`, `src/parse.cyr`) branches by shape: `local =
  true` → LOCAL; else `github_release` present (requires `release_asset` +
  `sha256`) → GITHUB; else `url` (requires `sha256`) → URL; else invalid.
- **Validator** (`src/validate.cyr`) switches on `kind`: URL keeps the
  https-scheme + sha256 checks; GITHUB requires `owner/repo` form +
  `release_asset` + sha256 shape; LOCAL has no source checks (meta package).

**Parse vs. fetch is deliberately split.** 0.9.0 only *models and validates*
these shapes. Actually *resolving* a `github_release` to a concrete asset URL
(and downloading any source) needs the network and lands with the deferred
download item — so `src_url` is empty for GITHUB/LOCAL kinds, and the `.ark`
manifest's `source_url` is empty for them until fetch resolves it.

## Consequences

- **All 563 zugot recipes now parse.** 539 fully validate; the remaining 24
  are correctly rejected — they carry placeholder empty `sha256 = ""` (upstream
  draft recipes), which takumi must reject (integrity requirement). The
  integration harness records 539/563 as the validate baseline and gates
  against regression below it.
- `SrcKind` is an in-memory tag only (not serialized into `.ark`), so its
  values are free to evolve; the struct-offset additions don't affect any
  on-disk format.
- A clean seam for the fetch work: the download item resolves
  GITHUB→asset-URL and fills `source_url`, reusing the existing
  `verify_source_hash` + `extract_archive` pipeline.

## Alternatives considered

- **Keep URL-only, preprocess recipes upstream** — pushes takumi's gap onto
  zugot tooling; rejected, takumi must read real recipes.
- **One combined fetch+model change** — rejected; resolving GitHub assets needs
  the network (its own surface). Modeling now, fetching later keeps 0.9.0
  hermetic and testable.
