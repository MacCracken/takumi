# Benchmarks

Parity baseline: the Cyrius port of each Rust benchmark, measured on
the same host. Rust numbers are from `rust-old/target/bench-history/`
(Criterion, `cargo bench`, std `sha2` crate). Cyrius numbers are from
`./build/takumi-bench` (`lib/bench.cyr`, pure-Cyrius SHA-256 via
`lib/sigil.cyr`).

Run locally:

```sh
cyrius build tests/takumi.bcyr build/takumi-bench
./build/takumi-bench
# or archive under build/bench-history/:
./scripts/bench-history.sh
```

## Parity results (2026-04-21, x86_64 Linux)

| Benchmark                       | Rust   | Cyrius  | Cyrius / Rust |
|---------------------------------|--------|---------|---------------|
| `parse_minimal_recipe`          |   —    |    9 µs | —             |
| `parse_full_recipe`             | 16.7 µs |   29 µs | 1.74×         |
| `validate_recipe`               |   —    |    1 µs | —             |
| `generate_cflags`               |   —    |    1 µs | —             |
| `generate_ldflags_with_dedup`   |   —    |  603 ns | —             |
| `resolve_build_order_10`        |   —    |   10 µs | —             |
| `resolve_build_order_100`       |   —    |  177 µs | —             |
| `resolve_build_order_300`       |  134 µs |  540 µs | 4.03×         |
| `create_file_list_26_files`     |  219 µs |  481 µs | 2.20×         |
| `sha256_1kb`                    |   —    |   70 µs | —             |
| `sha256_1mb`                    |  516 µs | 67.26 ms | **130×**     |

Rust rows without a value are benches that weren't reported in the
archived baselines (only the four above had published numbers in the
0.1.0 scaffold). The Cyrius numbers land in the expected 1.7–4× range
for code ported straight to the reference implementation, with one
outlier:

**SHA-256 is ~130× slower.** `lib/sigil.cyr` ships a portable
Cyrius SHA-256 implementation; Rust's `sha2` crate uses
hand-vectorized assembly with SHA-NI / AVX2 intrinsics. Closing this
gap is an upstream-sigil item (vectorized kernel), not a takumi
concern. For takumi's actual workload — tens to hundreds of
small-to-medium files per recipe — the absolute time remains in the
single-digit milliseconds at the high end and is dominated by I/O.

## Dropped: `manifest_json_roundtrip`

The Rust bench measured `serde_json::to_string` + `from_str` through
`ArkManifest`. The Cyrius port has no serde; the equivalent path is
the 13-store `man_alloc` + `man_set_*` sequence, which is O(13
memory writes) and already factored into the `validate_recipe`
timings. Once the `.ark` on-disk format lands (0.9.x) a
`manifest_encode_roundtrip` bench will replace this entry.

## Methodology

Each Cyrius bench follows the batched pattern recommended by
`lib/bench.cyr` — `bench_batch_start` / tight loop / `bench_batch_stop`
— so the ~120 ns `clock_gettime` overhead amortizes across the batch
and doesn't dominate sub-microsecond operations. Batch sizes:

| Bench class                | Iterations |
|----------------------------|-----------|
| Sub-µs (flags, validate)   | 10 000 – 100 000 |
| Parse                      | 1 000      |
| Kahn 10 / 100 / 300        | 10 000 / 1 000 / 500 |
| File walk + hash           | 100        |
| SHA-256 (1 KB / 1 MB)      | 10 000 / 100 |
