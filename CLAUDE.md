# Takumi — Claude Code Instructions

## Project Identity

**Takumi** (Japanese: 匠 — master craftsman) — Package build system for AGNOS (.ark packages from TOML recipes)

- **Type**: Binary
- **Language**: Cyrius (toolchain pinned to 5.5.23). Rust reference remains
  under `rust-old/` during the port and is authoritative until feature
  parity is reached.
- **License**: GPL-3.0-only
- **Version**: SemVer 0.1.0 (source of truth: `VERSION` → mirrored in `cyrius.cyml`)
- **Genesis repo**: [agnosticos](https://github.com/MacCracken/agnosticos)
- **Philosophy**: [AGNOS Philosophy & Intention](https://github.com/MacCracken/agnosticos/blob/main/docs/philosophy.md)
- **First-party standards**: [First-Party Application Standards](https://github.com/MacCracken/agnosticos/blob/main/docs/development/applications/first-party-standards.md)
- **Recipe repo**: [zugot](https://github.com/MacCracken/zugot) — takumi build recipes

## Consumers

ark (builds packages from zugot recipes). Takumi reads TOML recipes from the zugot repo and produces .ark packages for installation.

## Development Process

### P(-1): Scaffold Hardening (before any new features)

0. Read roadmap, CHANGELOG, and open issues — know what was intended before auditing what was built
1. Test + benchmark sweep of existing code
2. Cleanliness check: `cyrius fmt src/*.cyr --check`, `cyrius lint src/*.cyr` (0 warnings), `cyrius vet src/main.cyr`, `cyrius deny src/main.cyr`, `cyrius doc --check src/main.cyr`. `cyrius audit` bundles self-host + test + fmt + lint and is the canonical umbrella check.
3. Get baseline benchmarks (`cyrius bench tests/takumi.bcyr` + `./scripts/bench-history.sh`)
4. Internal deep review — gaps, optimizations, security, logging/errors, docs
5. External research — domain completeness, missing capabilities, best practices, world-class accuracy
6. Cleanliness check — must be clean after review
7. Additional tests/benchmarks from findings
8. Post-review benchmarks — prove the wins
9. Documentation audit (see [Documentation Standards](#documentation-standards))
10. Repeat if heavy

### Work Loop / Working Loop (continuous)

1. Work phase — new features, roadmap items, bug fixes
2. Cleanliness check: `cyrius fmt src/*.cyr --check`, `cyrius lint src/*.cyr` (0 warnings), `cyrius vet src/main.cyr`, `cyrius deny src/main.cyr`, `cyrius doc --check src/main.cyr` (or `cyrius audit` for the bundled equivalent)
3. Test + benchmark additions for new code (`tests/*.tcyr`, `tests/*.bcyr`)
4. Run benchmarks (`cyrius bench tests/takumi.bcyr` + `./scripts/bench-history.sh` when present)
5. Internal review — performance, memory, security, throughput, correctness
6. Cleanliness check — must be clean after review
7. Deeper tests/benchmarks from review observations
8. Run benchmarks again — prove the wins
9. If review heavy → return to step 5
10. Documentation — update CHANGELOG, roadmap, docs, ADRs, source citations (see [Documentation Standards](#documentation-standards))
11. Version check — `VERSION`, `cyrius.cyml` (`version =`), and the recipe in zugot all in sync
12. Return to step 1

### Task Sizing

- **Low/Medium effort**: Batch freely — multiple items per work loop cycle
- **Large effort**: Small bites only — break into sub-tasks, verify each before moving to the next. Never batch large items together
- **If unsure**: Treat it as large. Smaller bites are always safer than overcommitting

### Refactoring

- Refactor when the code tells you to — duplication, unclear boundaries, performance bottlenecks
- Never refactor speculatively. Wait for the third instance before extracting an abstraction
- Refactoring is part of the work loop, not a separate phase. If a review (step 5) reveals structural issues, refactor before moving to step 6
- Every refactor must pass the same cleanliness + benchmark gates as new code

### Key Principles

- Never skip benchmarks
- Enum discriminants are stable: explicit `= N` on every variant, never
  renumber (they appear in `.ark` manifests and on-disk state)
- Prefer pure functions; isolate I/O behind explicit entry points
- Gate optional modules with `#ifdef` — consumers pull only what they need
- No aborts from library code: no `assert(...)` in lib paths, no
  out-of-bounds `vec_get`/`map_get` on caller-controlled indices
  (validate first, or route through checked wrappers)
- Every type must have a canonical string form and a roundtrip test
  (`x_to_cstr` ↔ `x_from_cstr`, TOML in ↔ out)
- Builds must be reproducible — same recipe + same sources = identical .ark output
- SHA-256 integrity on all source downloads and produced artifacts (use
  `lib/sigil.cyr` — `sha256_digest` / `sha256_digest_bytes`)
- Recipe validation must be strict — reject malformed TOML early with clear errors
- Always call `alloc_init()` before any `alloc()` path (including tests)
- Pin toolchain to a released Cyrius tag in `cyrius.cyml`; never a dev version

## DO NOT

- **Do not commit or push** — the user handles all git operations
- **NEVER use `gh` CLI** — use `curl` to GitHub API only
- Do not add unnecessary dependencies
- Do not break backward compatibility without a major version bump
- Do not skip benchmarks before claiming performance improvements
- Do not produce packages without SHA-256 checksums
- Do not silently accept malformed recipes — fail loud and early

## Documentation Standards

Documentation is not a phase — it is part of every step. Every P(-1) audit and every work loop cycle must verify documentation is current.

### Required Structure

```
Root files (required):
  README.md          — what it is, how to use it, quick start
  CHANGELOG.md       — every change, every version
  CLAUDE.md          — this file (Claude Code instructions)
  CONTRIBUTING.md    — how to contribute
  SECURITY.md        — vulnerability reporting
  CODE_OF_CONDUCT.md — community standards
  LICENSE            — GPL-3.0-only

docs/ (required):
  architecture/overview.md  — module map, data flow, consumers
  development/roadmap.md    — completed, backlog, future, v1.0 criteria

docs/ (when earned):
  adr/                      — architectural decision records (see below)
  guides/                   — usage guides, integration patterns
  examples/                 — worked examples with explanation
  standards/                — compliance, conformance, spec references
  compliance/               — regulatory, licensing, security compliance
```

### Architectural Decision Records (ADRs)

Record significant design decisions in `docs/adr/` using the format:

```
docs/adr/
  NNNN-short-title.md
```

Each ADR must include:
- **Context** — what problem or choice prompted the decision
- **Decision** — what was decided and why
- **Consequences** — what follows from this decision (trade-offs, constraints)
- **Status** — proposed / accepted / deprecated / superseded

Create an ADR when:
- Choosing between competing approaches (algorithms, data structures, protocols)
- Adopting or rejecting a dependency
- Changing a public API in a breaking way
- Choosing a performance trade-off (speed vs memory, latency vs throughput)

### Guides and Examples

- **Guides** (`docs/guides/`) — written for consumers of this crate. How to integrate, common patterns, migration between versions.
- **Examples** (`examples/` or `docs/examples/`) — working code with comments explaining *why*, not just *what*. Every public API should have at least one example.

### Standards and Compliance

- **Standards** (`docs/standards/`) — reference external specifications this crate implements or conforms to. Link to the spec, note the version, document any deviations.
- **Compliance** (`docs/compliance/`) — regulatory, licensing, or security compliance documentation. Audit results, certification status, known limitations.

### Source Citations (Required for Science/Math/Domain Crates)

For crates that implement scientific, mathematical, financial, or domain-specific algorithms:

**In code** — every algorithm, formula, constant, or domain model must cite its source.

**In docs** — maintain a `docs/sources.md` or `docs/references.md` that lists:
- Every paper, textbook, or specification the crate draws from
- URLs to freely available versions where possible
- Which module or function uses which source
- Why a particular source was chosen over alternatives

**The standard**: a reviewer unfamiliar with the domain should be able to trace any algorithm back to its origin and verify the implementation against the published source. No magic numbers. No undocumented formulas. No "trust me, this is how it works."

## CHANGELOG Format

Follow [Keep a Changelog](https://keepachangelog.com/). Performance claims MUST include benchmark numbers. Breaking changes get a **Breaking** section with migration guide.
