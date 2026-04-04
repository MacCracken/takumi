# Contributing to Takumi

Takumi is the package build system for AGNOS. Contributions are welcome.

## Development Setup

```bash
# Clone
git clone https://github.com/MacCracken/takumi.git
cd takumi

# Rust 1.89+ required (see rust-toolchain.toml)
rustup update stable

# Build
cargo build

# Test
cargo test

# Benchmarks
./scripts/bench-history.sh
```

## Before Submitting

Every change must pass the cleanliness check:

```bash
cargo fmt --check
cargo clippy --all-features --all-targets -- -D warnings
cargo audit
cargo deny check
RUSTDOCFLAGS="-D warnings" cargo doc --all-features --no-deps
cargo test
```

## Coding Standards

- `#[non_exhaustive]` on all public enums
- `#[must_use]` on all pure functions
- Every type must derive `Serialize` and `Deserialize`
- All types must have serde roundtrip tests
- Zero `unwrap`/`panic` in library code
- Benchmarks before and after performance-related changes

See `CLAUDE.md` for the full development process and work loop.

## Reporting Issues

Open an issue at [github.com/MacCracken/takumi](https://github.com/MacCracken/takumi/issues).

## License

By contributing, you agree that your contributions will be licensed under
GPL-3.0-only.
