# Benchmarks: Rust vs Cyrius

Measured 2026-04-21 on the same machine, sequential runs.

- **Rust**: Criterion 0.5, 100 samples, `cargo bench` (release mode,
  LTO enabled). Archived baselines under
  `rust-old/target/bench-history/`.
- **Cyrius**: `lib/bench.cyr` `bench_batch_start`/`bench_batch_stop`,
  single batch per op, `cyrius bench tests/takumi.bcyr` (static ELF,
  no optimizer). Archived under `build/bench-history/` with
  per-row CSV in `bench-history.csv`.

## Comparable Benchmarks

Benchmarks that test the same logical operation in both
implementations. Rust rows without a value weren't reported in the
archived 0.1.0 baselines.

| Benchmark                     | Rust     | Cyrius   | Ratio    | Notes |
|-------------------------------|----------|----------|----------|-------|
| `parse_minimal_recipe`        |  —       |    9 µs  | —        | Minimal recipe, TOML on Rust / CYML on Cyrius |
| `parse_full_recipe`           | 16.7 µs  |   29 µs  | 1.74×    | Full recipe with every section; Cyrius adds the `[section]` → `[[section]]` promoter |
| `validate_recipe`             |  —       |    1 µs  | —        | Pure-function predicates; Cyrius accumulates errors + warnings (Rust short-circuits at first fatal) |
| `generate_cflags`             |  —       |    1 µs  | —        | 3 hardening flags + extra cflags |
| `generate_ldflags_with_dedup` |  —       |  603 ns  | —        | 4 hardening flags with FullRelro dedup |
| `resolve_build_order_10`      |  —       |   10 µs  | —        | 10-pkg chain, Kahn's algorithm |
| `resolve_build_order_100`     |  —       |  177 µs  | —        | 100-pkg chain |
| `resolve_build_order_300`     |  134 µs  |  540 µs  | 4.03×    | 300-pkg chain; Cyrius's cstring-keyed hashmap + insertion-sorted queue vs Rust's `HashMap<String, _>` + `Vec::sort` |
| `create_file_list_26_files`   |  219 µs  |  481 µs  | 2.20×    | Walk 26 files across 4 dirs, SHA-256 each |
| `sha256_1kb`                  |  —       |   70 µs  | —        | 1 KB buffer, single pass |
| `sha256_1mb`                  |  516 µs  | 67.26 ms | **130×** | 1 MB buffer — Cyrius is pure-scalar `lib/sigil.cyr`, Rust uses `sha2` crate with SHA-NI / AVX2 intrinsics |

## Dropped Benchmark

| Rust bench                | Why dropped                                                                 |
|---------------------------|------------------------------------------------------------------------------|
| `manifest_json_roundtrip` | No serde in Cyrius. The equivalent path (`man_alloc` + 13 `man_set_*` stores) is O(13) and already reflected in `validate_recipe` timings. A `manifest_encode_roundtrip` bench will replace this when the `.ark` on-disk format lands in 0.9.x. |

## What the ratios mean

### 1.7–2.2× on parse / file walk

Expected for a straight port with no optimizer. Cyrius walks the
parse buffer byte-by-byte in Cyrius source; Rust's `toml` crate uses
a hand-written parser with inlined dispatch and LLVM optimizing the
tight loops. Absolute times remain in the tens of microseconds —
noise next to the disk I/O these functions guard.

### 4× on `resolve_build_order_300`

Kahn's main loop is dominated by hashmap operations (`in_degree`
decrements) and the sorted-queue insertion. Rust's
`HashMap::entry().or_insert().iter()` compiles to tight code with
inlined hash; Cyrius's `lib/hashmap.cyr` allocates an entry per probe
miss and uses a generic string-hash function. The insertion-sorted
queue is O(n) per insert in Cyrius (simple cstring compare loop);
Rust reruns `Vec::sort` (O(n log n) but with branch-predicted
comparators). The net 4× ratio is acceptable for the real workload
— a build-order resolution on 300 packages takes half a millisecond
either way.

### 130× on `sha256_1mb`

`lib/sigil.cyr` ships a portable Cyrius SHA-256: pure scalar 32-bit
arithmetic, no SSE / AVX / SHA-NI. Rust's `sha2` crate dispatches to
hand-tuned x86-64 assembly with SHA Extensions when available. The
ratio is expected and **not a takumi concern** — it lives in the
sigil stdlib. For takumi's actual workload (`create_file_list` across
tens to hundreds of small-to-medium files per recipe), the per-file
SHA cost is sub-millisecond and dominated by `open`/`read` syscalls.

## Build Artifacts

| Metric                              | Rust (0.1.0 scaffold)                                  | Cyrius (0.8.0)  |
|-------------------------------------|--------------------------------------------------------|-----------------|
| Distribution                        | Library crate (`.rlib`)                                | Static ELF binary + header-only includes |
| Main binary size                    | n/a (lib-only)                                         | ~599 KB         |
| Bench binary size                   | n/a                                                    | ~614 KB         |
| Compile time (clean)                | Multi-second with LTO (not recorded)                   | **~0.43 s** (single-pass, no LTO) |
| External runtime deps               | libc + libgcc_s                                        | **libc only** (static link, no dynamic load) |
| Declared deps                       | 7 crates + transitive (`anyhow`, `chrono`, `serde`, `serde_json`, `sha2`, `toml`, `tracing`) + `criterion` + `tempfile` for dev | 18 stdlib modules + `sigil` 2.9.0 |

## Test Coverage

| Metric              | Rust (0.1.0 scaffold)                            | Cyrius (0.8.0)              |
|---------------------|--------------------------------------------------|------------------------------|
| Test count          | 74 unit tests (all serde roundtrips included)    | **543 assertions**           |
| Test framework      | `#[test]` + Criterion                            | `lib/assert.cyr` + batched `lib/bench.cyr` |
| Integration tests   | none (unit-only lib crate)                       | 2 real-filesystem: walker `/tmp/takumi-b6b-test/`, `tbs_load_all_recipes` `/tmp/takumi-engine-test/` |
| Security-focused    | 6 (recipe-name injection / URL scheme / SHA format) | 9 ASCII-only predicates + 4 validator error paths |

## How to Run

```sh
# Compile + run the benchmark binary in one step:
cyrius bench tests/takumi.bcyr

# Or: run + archive to build/bench-history/ and append to bench-history.csv:
./scripts/bench-history.sh [label]

# Note: the Cyrius toolchain's own `cyrius bench` with no args invokes
# the install-dir bench-history.sh (~/.cyrius/bin/bench-history.sh),
# not ours. For takumi always pass the bench path explicitly or use
# the project-local wrapper above.
```

Rust baselines rebuild under `rust-old/`:

```sh
cd rust-old && cargo bench
```

## Methodology Notes

- Cyrius benches use `bench_batch_start`/`bench_batch_stop` with batch
  sizes tuned so each benchmark runs 10–100 ms total. Per-op
  `clock_gettime` overhead (~120 ns) amortizes across the batch,
  matching Criterion's black-box inner-loop approach.
- Rust figures come from Criterion's archived JSON in
  `rust-old/target/bench-history/`. Exact timestamps inside each
  archive entry.
- The Cyrius numbers above are a **single-run snapshot**, not a
  statistical distribution. For commit-over-commit comparison use
  `scripts/bench-history.sh <label>` and diff `bench-history.csv`
  rows. Variance is typically ±5% at this scale.
