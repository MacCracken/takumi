# Contributing to Takumi

Takumi is the package build system for AGNOS. Contributions are welcome.

## Development Setup

Takumi is written in **Cyrius** (toolchain pinned in `cyrius.cyml`; currently
6.2.20). The original Rust implementation is kept under `rust-old/` for
historical reference only.

```bash
# Clone
git clone https://github.com/MacCracken/takumi.git
cd takumi

# Build the binary
cyrius build src/main.cyr build/takumi

# Test
cyrius test tests/takumi.tcyr

# Benchmarks
cyrius bench tests/takumi.bcyr
./scripts/bench-history.sh   # when present

# End-to-end integration (drives the real CLI)
bash scripts/integration.sh
```

## Before Submitting

Every change must pass the cleanliness check (the `cyrius audit` umbrella bundles
self-host + test + fmt + lint):

```bash
cyrius fmt src/*.cyr --check
cyrius lint src/*.cyr            # 0 warnings
cyrius vet src/main.cyr
cyrius deny src/main.cyr
cyrius doc --check src/main.cyr
cyrius test tests/takumi.tcyr
```

## Coding Standards

- Enum discriminants are stable: explicit `= N` on every variant, never renumber
  (they appear in `.ark` manifests and on-disk state).
- Every type has a canonical string form and a roundtrip test
  (`x_to_cstr` ↔ `x_from_cstr`; CYML in ↔ out).
- No aborts from library code: no `assert(...)` on caller-controlled paths, no
  out-of-bounds `vec_get`/`map_get` — validate first or use checked wrappers.
- Always call `alloc_init()` before any `alloc()` path (including tests).
- Add tests (`tests/*.tcyr`) and benchmarks (`tests/*.bcyr`) for new code;
  benchmark before and after performance-related changes.
- Keep the version in sync across `VERSION`, `cyrius.cyml`, the `src/package.cyr`
  builder stamp, `takumi_version()` in `src/cli.cyr`, and the zugot recipe.

See `CLAUDE.md` for the full development process and work loop.

## Reporting Issues

Open an issue at [github.com/MacCracken/takumi](https://github.com/MacCracken/takumi/issues).

## License

By contributing, you agree that your contributions will be licensed under
GPL-3.0-only.
