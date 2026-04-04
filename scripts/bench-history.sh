#!/usr/bin/env bash
# bench-history.sh — Run criterion benchmarks and archive the results.
#
# Usage:
#   ./scripts/bench-history.sh [label]
#
# If no label is given, the current git short-hash is used.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

LABEL="${1:-$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
HISTORY_DIR="$REPO_ROOT/target/bench-history"
ENTRY_DIR="$HISTORY_DIR/$TIMESTAMP-$LABEL"

mkdir -p "$ENTRY_DIR"

echo "=== Takumi Benchmark Run ==="
echo "Label:     $LABEL"
echo "Timestamp: $TIMESTAMP"
echo "Output:    $ENTRY_DIR"
echo ""

# Run benchmarks, saving output
cargo bench 2>&1 | tee "$ENTRY_DIR/output.txt"

# Copy criterion reports if they exist
if [ -d "$REPO_ROOT/target/criterion" ]; then
    cp -r "$REPO_ROOT/target/criterion" "$ENTRY_DIR/criterion"
fi

echo ""
echo "=== Benchmark results saved to $ENTRY_DIR ==="
echo ""

# Print summary: extract benchmark lines
grep -E "^(test |.*time:)" "$ENTRY_DIR/output.txt" || true
