#!/usr/bin/env bash
# bench-history.sh — Run takumi benchmarks and archive the results.
#
# Usage:
#   ./scripts/bench-history.sh [label]
#
# If no label is given, the current git short-hash is used. Appends a
# one-line-per-bench CSV row to `bench-history.csv` so numbers can be
# tracked across commits and compared against the Rust baseline in
# BENCHMARKS.md.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

LABEL="${1:-$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
HISTORY_DIR="$REPO_ROOT/build/bench-history"
ENTRY_DIR="$HISTORY_DIR/$TIMESTAMP-$LABEL"
CSV="$REPO_ROOT/bench-history.csv"

mkdir -p "$ENTRY_DIR"

echo "=== Takumi Benchmark Run ==="
echo "Label:     $LABEL"
echo "Timestamp: $TIMESTAMP"
echo "Output:    $ENTRY_DIR"
echo ""

# Build the bench binary and run it, teeing output.
cyrius build tests/takumi.bcyr build/takumi-bench
./build/takumi-bench 2>&1 | tee "$ENTRY_DIR/output.txt"

# Ensure CSV header exists (timestamp,label,bench,avg,min,max,iters).
if [ ! -f "$CSV" ]; then
    echo "timestamp,label,bench,avg,min,max,iters" > "$CSV"
fi

# Parse the bench output and append one row per benchmark. Expected
# line shape (from lib/bench.cyr's bench_report):
#   <name>: <avg>us avg (min=<min>us max=<max>us) [<N> iters]
awk -v ts="$TIMESTAMP" -v label="$LABEL" '
    /^[[:space:]]*[a-z][a-z0-9_]*: [0-9]+(\.[0-9]+)?(ns|us|ms) avg/ {
        gsub(/^[[:space:]]+/, "")
        name = $1; sub(":", "", name)
        avg = $2
        min = $4; sub("\\(min=", "", min)
        max = $5; sub("max=", "", max); sub("\\)", "", max)
        iters = $6; sub("\\[", "", iters)
        printf "%s,%s,%s,%s,%s,%s,%s\n", ts, label, name, avg, min, max, iters
    }
' "$ENTRY_DIR/output.txt" >> "$CSV"

echo ""
echo "=== Benchmark results saved to $ENTRY_DIR; summary appended to $CSV ==="
