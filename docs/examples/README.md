# Examples

Worked, annotated recipes. Each pairs a `.cyml` with a walkthrough of *why* it
looks the way it does.

- [hello](hello/) — GNU hello from a direct URL, with a real patch applied to
  the source before the build. Exercises the full pipeline: fetch → verify →
  extract → patch → build → package.

For the recipe format and the CLI, see the
[Building packages](../guides/building-packages.md) guide.

## Source-kind quick reference

A `[source]` is exactly one of three kinds:

```toml
# 1. Direct URL (https only)
[source]
url = "https://example.org/foo-1.0.tar.gz"
sha256 = "…64 hex chars…"

# 2. GitHub release asset (resolved via the releases API + glob)
[source]
github_release = "owner/repo"
release_asset = "foo-*-linux.tar.gz"
sha256 = "…64 hex chars…"

# 3. Local / meta package (no upstream to fetch)
[source]
local = true
```
