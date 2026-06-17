#!/usr/bin/env bash
# End-to-end integration harness: build the takumi binary and drive its CLI
# over real recipe fixtures, asserting exit codes (complements the in-process
# cli_dispatch unit tests in tests/takumi.tcyr).
#
# Optionally sweeps the full zugot corpus when present: set ZUGOT_DIR, or it
# auto-detects ../zugot. The sweep is informational + baseline-gated; it is
# NOT run in CI (CI stays self-contained on the vendored fixtures).
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BIN="build/takumi"
FIXTURES="tests/fixtures/recipes"
INVALID="tests/fixtures/invalid.cyml"
# Minimum fraction (percent) of the zugot corpus that must still validate,
# guarding against parser/validator regressions. Baseline at 0.9.0: 539/563.
ZUGOT_MIN_VALIDATE="${ZUGOT_MIN_VALIDATE:-539}"

fails=0
check() { # <description> <expected-exit> <actual-exit>
  if [ "$2" = "$3" ]; then
    echo "  ok   $1 (exit $3)"
  else
    echo "  FAIL $1 (expected $2, got $3)"
    fails=$((fails + 1))
  fi
}

echo "== build =="
mkdir -p build
CYRIUS_NO_WARN_SHADOW_LIB=1 CYRIUS_NO_WARN_PIN_DRIFT=1 \
  cyrius build src/main.cyr "$BIN" >/dev/null 2>&1 || { echo "BUILD FAILED"; exit 1; }
echo "  built $BIN"

echo "== cli surface =="
"$BIN" version >/dev/null 2>&1;       check "version" 0 $?
"$BIN" help >/dev/null 2>&1;          check "help" 0 $?
"$BIN" >/dev/null 2>&1;               check "no args -> usage" 0 $?
"$BIN" frobnicate >/dev/null 2>&1;    check "unknown -> usage error" 2 $?

echo "== validate fixtures (one per source shape) =="
for f in "$FIXTURES"/*.cyml; do
  "$BIN" validate "$f" >/dev/null 2>&1
  check "validate $(basename "$f")" 0 $?
done
"$BIN" validate "$INVALID" >/dev/null 2>&1; check "validate invalid.cyml" 1 $?

echo "== list / order / build over fixtures dir =="
"$BIN" list "$FIXTURES" >/dev/null 2>&1;   check "list" 0 $?
"$BIN" order "$FIXTURES" >/dev/null 2>&1;  check "order" 0 $?
"$BIN" build "$FIXTURES" >/dev/null 2>&1;  check "build (dry-run plan)" 2 $?

# Optional: validate the whole zugot corpus (regression guard, local only).
ZUGOT="${ZUGOT_DIR:-../zugot}"
if [ -d "$ZUGOT" ]; then
  echo "== zugot corpus sweep ($ZUGOT) =="
  pass=0; total=0
  while IFS= read -r r; do
    total=$((total + 1))
    "$BIN" validate "$r" >/dev/null 2>&1 && pass=$((pass + 1))
  done < <(find "$ZUGOT" -name '*.cyml')
  echo "  validates $pass / $total (all parse; non-validating recipes carry empty source sha256)"
  if [ "$pass" -lt "$ZUGOT_MIN_VALIDATE" ]; then
    echo "  FAIL corpus regression: $pass < baseline $ZUGOT_MIN_VALIDATE"
    fails=$((fails + 1))
  fi
else
  echo "== zugot corpus sweep skipped (no $ZUGOT) =="
fi

echo
if [ "$fails" -eq 0 ]; then
  echo "integration: PASS"
  exit 0
else
  echo "integration: $fails FAILED"
  exit 1
fi
