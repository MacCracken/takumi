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

echo "== build --execute over a LOCAL-only dir (no network) =="
rm -rf /tmp/takumi-build /tmp/takumi-it-local
mkdir -p /tmp/takumi-it-local
cp "$FIXTURES/libgbm.cyml" /tmp/takumi-it-local/    # local meta-package, no source
"$BIN" build /tmp/takumi-it-local --execute >/dev/null 2>&1; check "build --execute (local)" 0 $?
if [ -f /tmp/takumi-build/out/libgbm.ark ]; then
  echo "  ok   local package produced libgbm.ark"
else
  echo "  FAIL no .ark produced for the local package"
  fails=$((fails + 1))
fi
rm -rf /tmp/takumi-build /tmp/takumi-it-local

# Full fetch -> verify -> extract -> build -> package over a LOOPBACK server
# (no external network; proves the real download path end to end). Needs
# python3 + tar; skipped otherwise.
if command -v python3 >/dev/null 2>&1 && command -v tar >/dev/null 2>&1; then
  echo "== build --execute over loopback HTTP (real fetch) =="
  SRV=/tmp/takumi-it-srv; REC=/tmp/takumi-it-rec
  rm -rf "$SRV" "$REC" /tmp/takumi-build; mkdir -p "$SRV/pkgsrc" "$REC"
  echo "loopback source" > "$SRV/pkgsrc/README"
  tar czf "$SRV/demo-1.0.tar.gz" -C "$SRV" pkgsrc
  SHA=$(sha256sum "$SRV/demo-1.0.tar.gz" | cut -d' ' -f1)
  {
    echo '[package]'; echo 'name = "demo"'; echo 'version = "1.0"'
    echo 'description = "loopback fetch demo"'; echo 'license = "MIT"'; echo
    echo '[source]'; echo 'url = "http://127.0.0.1:8097/demo-1.0.tar.gz"'
    echo "sha256 = \"$SHA\""; echo
    # cwd is the extracted tarball root (pkgsrc/), so README is at ./README.
    echo '[build]'; echo 'install = "mkdir -p $PKG/usr/share && cp README $PKG/usr/share/demo-README"'
  } > "$REC/demo.cyml"
  ( cd "$SRV" && python3 -m http.server 8097 >/dev/null 2>&1 & echo $! > /tmp/takumi-it-srv.pid )
  sleep 1
  "$BIN" build "$REC" --execute >/dev/null 2>&1; check "build --execute (loopback fetch)" 0 $?
  if [ -f /tmp/takumi-build/out/demo.ark ] && [ -f /tmp/takumi-build/demo/pkg/usr/share/demo-README ]; then
    echo "  ok   fetched, verified, extracted, built, packaged demo.ark"
  else
    echo "  FAIL loopback build did not produce the expected artifacts"
    fails=$((fails + 1))
  fi
  kill "$(cat /tmp/takumi-it-srv.pid 2>/dev/null)" 2>/dev/null
  rm -rf "$SRV" "$REC" /tmp/takumi-build /tmp/takumi-it-srv.pid
else
  echo "== loopback fetch test skipped (needs python3 + tar) =="
fi

# Patch application end to end: fetch -> verify -> extract -> APPLY PATCH ->
# build -> package, with a real unified diff (system `diff`). Needs python3 +
# tar + diff; skipped otherwise.
if command -v python3 >/dev/null 2>&1 && command -v tar >/dev/null 2>&1 && command -v diff >/dev/null 2>&1; then
  echo "== build --execute with a patch (real unified diff) =="
  SRV=/tmp/takumi-it-psrv; REC=/tmp/takumi-it-prec
  rm -rf "$SRV" "$REC" /tmp/takumi-build; mkdir -p "$SRV/pkgsrc" "$REC"
  # pristine source served to takumi; the patch flips greeting -> patched.
  printf 'greeting = "world"\n' > "$SRV/pkgsrc/app.conf"
  tar czf "$SRV/demo-1.0.tar.gz" -C "$SRV" pkgsrc
  SHA=$(sha256sum "$SRV/demo-1.0.tar.gz" | cut -d' ' -f1)
  # generate a genuine unified diff (a/ b/ prefixes -> -p1 strips them).
  mkdir -p /tmp/takumi-it-diff/a /tmp/takumi-it-diff/b
  printf 'greeting = "world"\n' > /tmp/takumi-it-diff/a/app.conf
  printf 'greeting = "patched"\n' > /tmp/takumi-it-diff/b/app.conf
  ( cd /tmp/takumi-it-diff && diff -u a/app.conf b/app.conf > "$REC/greeting.patch" || true )
  {
    echo '[package]'; echo 'name = "demo"'; echo 'version = "1.0"'
    echo 'description = "loopback patch demo"'; echo 'license = "MIT"'; echo
    echo '[source]'; echo 'url = "http://127.0.0.1:8099/demo-1.0.tar.gz"'
    echo "sha256 = \"$SHA\""; echo 'patches = ["greeting.patch"]'; echo
    # cwd is the extracted tarball root (pkgsrc/), so app.conf is at ./app.conf.
    # The build asserts the patch applied (new value present, old value gone).
    echo '[build]'; echo 'install = "grep -q patched app.conf && ! grep -q world app.conf && mkdir -p $PKG/etc && cp app.conf $PKG/etc/demo.conf"'
  } > "$REC/demo.cyml"
  ( cd "$SRV" && python3 -m http.server 8099 >/dev/null 2>&1 & echo $! > /tmp/takumi-it-psrv.pid )
  sleep 1
  "$BIN" build "$REC" --execute >/dev/null 2>&1; check "build --execute (patch applied)" 0 $?
  if [ -f /tmp/takumi-build/out/demo.ark ] && grep -q patched /tmp/takumi-build/demo/pkg/etc/demo.conf 2>/dev/null; then
    echo "  ok   patch applied to the extracted source, build saw the change"
  else
    echo "  FAIL patch was not applied end to end"
    fails=$((fails + 1))
  fi
  kill "$(cat /tmp/takumi-it-psrv.pid 2>/dev/null)" 2>/dev/null
  rm -rf "$SRV" "$REC" /tmp/takumi-build /tmp/takumi-it-diff /tmp/takumi-it-psrv.pid
else
  echo "== patch test skipped (needs python3 + tar + diff) =="
fi

# PAX-format tarball end to end: a real `tar --format=pax` archive with a path
# over the 100-byte ustar limit (forcing a PAX 'x' path record) + the global
# 'g' header pax always emits. Confirms extraction reconstructs the long path.
# Needs python3 + tar; skipped otherwise.
if command -v python3 >/dev/null 2>&1 && command -v tar >/dev/null 2>&1; then
  echo "== build --execute over a PAX tarball (long path) =="
  SRV=/tmp/takumi-it-xsrv; REC=/tmp/takumi-it-xrec
  rm -rf "$SRV" "$REC" /tmp/takumi-build; mkdir -p "$REC"
  # a path well over 100 bytes so tar must emit a PAX 'x' path record.
  DEEP="pkgsrc/a-rather-deeply-nested-directory-name/and-another-long-segment-here/plus-one-more-to-be-safe"
  mkdir -p "$SRV/$DEEP"
  echo "pax-long-path-payload" > "$SRV/$DEEP/payload.txt"
  echo "top" > "$SRV/pkgsrc/top.txt"
  tar --format=pax -czf "$SRV/demo-1.0.tar.gz" -C "$SRV" pkgsrc
  SHA=$(sha256sum "$SRV/demo-1.0.tar.gz" | cut -d' ' -f1)
  {
    echo '[package]'; echo 'name = "demo"'; echo 'version = "1.0"'
    echo 'description = "loopback pax demo"'; echo 'license = "MIT"'; echo
    echo '[source]'; echo 'url = "http://127.0.0.1:8101/demo-1.0.tar.gz"'
    echo "sha256 = \"$SHA\""; echo
    # cwd is the extracted root (pkgsrc/). The build asserts the long PAX path
    # was reconstructed, then copies it into the fake-root.
    echo '[build]'; echo 'install = "test -f a-rather-deeply-nested-directory-name/and-another-long-segment-here/plus-one-more-to-be-safe/payload.txt && mkdir -p $PKG/etc && cp a-rather-deeply-nested-directory-name/and-another-long-segment-here/plus-one-more-to-be-safe/payload.txt $PKG/etc/pax.txt"'
  } > "$REC/demo.cyml"
  ( cd "$SRV" && python3 -m http.server 8101 >/dev/null 2>&1 & echo $! > /tmp/takumi-it-xsrv.pid )
  sleep 1
  "$BIN" build "$REC" --execute >/dev/null 2>&1; check "build --execute (PAX long path)" 0 $?
  if [ -f /tmp/takumi-build/out/demo.ark ] && grep -q pax-long-path-payload /tmp/takumi-build/demo/pkg/etc/pax.txt 2>/dev/null; then
    echo "  ok   PAX 'x'/'g' headers parsed, long path reconstructed end to end"
  else
    echo "  FAIL PAX long path was not reconstructed"
    fails=$((fails + 1))
  fi
  kill "$(cat /tmp/takumi-it-xsrv.pid 2>/dev/null)" 2>/dev/null
  rm -rf "$SRV" "$REC" /tmp/takumi-build /tmp/takumi-it-xsrv.pid
else
  echo "== PAX test skipped (needs python3 + tar) =="
fi

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
