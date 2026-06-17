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
# (no external network; proves the real download path end to end). The fetch
# now streams the body straight to disk (sandhi_http_download, 0.9.7), so this
# exercises the streaming path. Needs python3 + tar; skipped otherwise.
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

# GNU-format tarball end to end (0.10.2): a real `tar --format=gnu` archive with
# a path over 100 bytes (forcing a GNU 'L' long-name header). Confirms extraction
# reconstructs the long path. Needs python3 + tar; skipped otherwise.
if command -v python3 >/dev/null 2>&1 && command -v tar >/dev/null 2>&1; then
  echo "== build --execute over a GNU tarball (long name) =="
  SRV=/tmp/takumi-it-gsrv; REC=/tmp/takumi-it-grec
  rm -rf "$SRV" "$REC" /tmp/takumi-build; mkdir -p "$REC"
  DEEP="pkgsrc/a-rather-deeply-nested-directory-name/and-another-long-segment-here/plus-one-more-to-be-safe"
  mkdir -p "$SRV/$DEEP"
  echo "gnu-long-name-payload" > "$SRV/$DEEP/payload.txt"
  echo "top" > "$SRV/pkgsrc/top.txt"
  tar --format=gnu -czf "$SRV/demo-1.0.tar.gz" -C "$SRV" pkgsrc
  SHA=$(sha256sum "$SRV/demo-1.0.tar.gz" | cut -d' ' -f1)
  {
    echo '[package]'; echo 'name = "demo"'; echo 'version = "1.0"'
    echo 'description = "loopback gnu demo"'; echo 'license = "MIT"'; echo
    echo '[source]'; echo 'url = "http://127.0.0.1:8103/demo-1.0.tar.gz"'
    echo "sha256 = \"$SHA\""; echo
    echo '[build]'; echo 'install = "test -f a-rather-deeply-nested-directory-name/and-another-long-segment-here/plus-one-more-to-be-safe/payload.txt && mkdir -p $PKG/etc && cp a-rather-deeply-nested-directory-name/and-another-long-segment-here/plus-one-more-to-be-safe/payload.txt $PKG/etc/gnu.txt"'
  } > "$REC/demo.cyml"
  ( cd "$SRV" && python3 -m http.server 8103 >/dev/null 2>&1 & echo $! > /tmp/takumi-it-gsrv.pid )
  sleep 1
  "$BIN" build "$REC" --execute >/dev/null 2>&1; check "build --execute (GNU long name)" 0 $?
  if [ -f /tmp/takumi-build/out/demo.ark ] && grep -q gnu-long-name-payload /tmp/takumi-build/demo/pkg/etc/gnu.txt 2>/dev/null; then
    echo "  ok   GNU 'L' long-name header parsed, long path reconstructed end to end"
  else
    echo "  FAIL GNU long name was not reconstructed"
    fails=$((fails + 1))
  fi
  kill "$(cat /tmp/takumi-it-gsrv.pid 2>/dev/null)" 2>/dev/null
  rm -rf "$SRV" "$REC" /tmp/takumi-build /tmp/takumi-it-gsrv.pid
else
  echo "== GNU test skipped (needs python3 + tar) =="
fi

# Real compilation end to end (0.10.1): fetch -> verify -> extract -> build a
# tiny C program with `make` (using the real toolchain) -> install into $PKG ->
# package, over loopback (no external network). A best-effort demonstration —
# real compilation under the full unprivileged sandbox varies by runner kernel /
# Landlock ABI / toolchain, so it is tolerant (see below). The hard guarantees
# are covered by hermetic tests + the live GNU hello build (ADR 0013).
# Needs python3 + tar + gcc + make; skipped otherwise.
if command -v python3 >/dev/null 2>&1 && command -v tar >/dev/null 2>&1 \
   && command -v gcc >/dev/null 2>&1 && command -v make >/dev/null 2>&1; then
  echo "== build --execute real compile (gcc + make) =="
  SRV=/tmp/takumi-it-csrv; REC=/tmp/takumi-it-crec
  rm -rf "$SRV" "$REC" /tmp/takumi-build; mkdir -p "$SRV/cprog" "$REC"
  printf '#include <stdio.h>\nint main(void){puts("built-by-takumi");return 0;}\n' > "$SRV/cprog/hello.c"
  printf 'all: prog\nprog: hello.c\n\t$(CC) -O2 -o prog hello.c\ninstall:\n\tmkdir -p $(DESTDIR)/usr/bin\n\tcp prog $(DESTDIR)/usr/bin/cprog\n' > "$SRV/cprog/Makefile"
  tar czf "$SRV/cprog-1.0.tar.gz" -C "$SRV" cprog
  SHA=$(sha256sum "$SRV/cprog-1.0.tar.gz" | cut -d' ' -f1)
  {
    echo '[package]'; echo 'name = "cprog"'; echo 'version = "1.0"'
    echo 'description = "real compile demo"'; echo 'license = "MIT"'; echo
    echo '[source]'; echo 'url = "http://127.0.0.1:8102/cprog-1.0.tar.gz"'
    echo "sha256 = \"$SHA\""; echo
    echo '[build]'; echo 'make = "make"'; echo 'install = "make DESTDIR=$PKG install"'
  } > "$REC/cprog.cyml"
  ( cd "$SRV" && python3 -m http.server 8102 >/dev/null 2>&1 & echo $! > /tmp/takumi-it-csrv.pid )
  sleep 1
  # Tolerant + diagnostic: a real gcc compile under an unprivileged
  # user+net+Landlock sandbox depends on the runner's kernel / Landlock ABI /
  # toolchain layout, so a failure here is reported (with a diagnostic tail) but
  # does NOT fail the suite. The hard guarantees — extraction mode/mtime
  # preservation and the build PATH — are covered by hermetic tests
  # (tests/takumi.tcyr) and the documented live GNU hello build (ADR 0013).
  "$BIN" build "$REC" --execute >/tmp/takumi-it-creal.log 2>&1
  BIN_OUT=/tmp/takumi-build/cprog/pkg/usr/bin/cprog
  if [ -x "$BIN_OUT" ] && [ "$("$BIN_OUT" 2>/dev/null)" = "built-by-takumi" ]; then
    echo "  ok   compiled a real C program with make, installed + runs"
  else
    echo "  note real compile not reproduced on this runner (env-dependent; not a gate)"
    echo "       --- build output (tail) ---"
    tail -n 15 /tmp/takumi-it-creal.log 2>/dev/null | sed 's/^/       /'
  fi
  kill "$(cat /tmp/takumi-it-csrv.pid 2>/dev/null)" 2>/dev/null
  rm -rf "$SRV" "$REC" /tmp/takumi-build /tmp/takumi-it-csrv.pid /tmp/takumi-it-creal.log
else
  echo "== real-compile test skipped (needs python3 + tar + gcc + make) =="
fi

# Build sandbox: network isolation (0.9.8). A build step records how many
# network interfaces it sees via /proc/net/dev (per-netns). When the CLI reports
# isolation active, the step must see exactly 1 (loopback) — proof the build ran
# in a fresh network namespace. Tolerant: where unprivileged user namespaces are
# unavailable (CI seccomp, userns disabled), isolation is "unavailable" and we
# only assert the build still succeeded (the timeout always applies).
echo "== build --execute network isolation (sandbox) =="
NSREC=/tmp/takumi-it-nsrec
rm -rf "$NSREC" /tmp/takumi-build; mkdir -p "$NSREC"
{
  echo '[package]'; echo 'name = "netcheck"'; echo 'version = "1.0"'
  echo 'description = "sandbox netns check"'; echo 'license = "MIT"'; echo
  echo '[source]'; echo 'local = true'; echo
  echo '[build]'; echo 'install = "mkdir -p $PKG/etc && grep -c : /proc/net/dev > $PKG/etc/nif.txt"'
} > "$NSREC/netcheck.cyml"
NSOUT=$("$BIN" build "$NSREC" --execute 2>&1); nsrc=$?
check "build --execute (sandbox build ok)" 0 $nsrc
NIF=$(cat /tmp/takumi-build/netcheck/pkg/etc/nif.txt 2>/dev/null)
if echo "$NSOUT" | grep -q "isolation: active"; then
  if [ "$NIF" = "1" ]; then
    echo "  ok   network isolation active: build saw 1 interface (loopback only)"
  else
    echo "  FAIL isolation reported active but build saw $NIF interfaces"
    fails=$((fails + 1))
  fi
else
  echo "  ok   isolation unavailable here (userns off); build still ran, time-bounded"
fi
rm -rf "$NSREC" /tmp/takumi-build

# Build sandbox: filesystem confinement (0.10.0). A build step tries to write to
# a user-writable path OUTSIDE the build/temp area (so the block is Landlock, not
# file permissions) and also writes into $PKG. When the CLI reports confinement
# active, the escape must be blocked ("confined") and the $PKG write must
# succeed. Tolerant: where Landlock is unavailable we only assert the build ran.
echo "== build --execute filesystem confinement (Landlock) =="
FSREC=/tmp/takumi-it-fsrec
# A path the build user can normally write but that is NOT a granted area.
# /tmp is granted (it holds the build root), so put the probe under $HOME.
FSPROBE="$HOME/.takumi-it-fsprobe"
rm -rf "$FSREC" "$FSPROBE" /tmp/takumi-build; mkdir -p "$FSREC" "$FSPROBE"
{
  echo '[package]'; echo 'name = "fscheck"'; echo 'version = "1.0"'
  echo 'description = "sandbox landlock check"'; echo 'license = "MIT"'; echo
  echo '[source]'; echo 'local = true'; echo
  echo '[build]'; echo "install = \"mkdir -p \$PKG/etc && (touch $FSPROBE/escaped 2>/dev/null && echo escaped || echo confined) > \$PKG/etc/fs.txt\""
} > "$FSREC/fscheck.cyml"
FSOUT=$("$BIN" build "$FSREC" --execute 2>&1); fsrc=$?
check "build --execute (sandbox fs build ok)" 0 $fsrc
FSRES=$(cat /tmp/takumi-build/fscheck/pkg/etc/fs.txt 2>/dev/null)
if echo "$FSOUT" | grep -q "filesystem confinement: active"; then
  if [ "$FSRES" = "confined" ] && [ ! -e "$FSPROBE/escaped" ]; then
    echo "  ok   Landlock active: write outside the build area was blocked"
  else
    echo "  FAIL confinement reported active but escape was '$FSRES' (file present: $([ -e "$FSPROBE/escaped" ] && echo yes || echo no))"
    fails=$((fails + 1))
  fi
else
  echo "  ok   Landlock unavailable here; build still ran, time-bounded"
fi
rm -rf "$FSREC" "$FSPROBE" /tmp/takumi-build

# Reproducibility (0.9.9): the same recipe built twice with a fixed
# SOURCE_DATE_EPOCH must yield a byte-identical .ark (the build timestamp is the
# only otherwise-floating input; the .ark writer is already deterministic).
echo "== reproducible build (SOURCE_DATE_EPOCH -> identical .ark) =="
RREC=/tmp/takumi-it-rrec
rm -rf "$RREC" /tmp/takumi-build /tmp/takumi-it-repro-a.ark /tmp/takumi-it-repro-b.ark; mkdir -p "$RREC"
{
  echo '[package]'; echo 'name = "repro"'; echo 'version = "1.0"'
  echo 'description = "reproducibility check"'; echo 'license = "MIT"'; echo
  echo '[source]'; echo 'local = true'; echo
  echo '[build]'; echo 'install = "mkdir -p $PKG/usr/share && printf payload > $PKG/usr/share/repro.txt"'
} > "$RREC/repro.cyml"
SOURCE_DATE_EPOCH=1700000000 "$BIN" build "$RREC" --execute >/dev/null 2>&1
cp /tmp/takumi-build/out/repro.ark /tmp/takumi-it-repro-a.ark 2>/dev/null
rm -rf /tmp/takumi-build
SOURCE_DATE_EPOCH=1700000000 "$BIN" build "$RREC" --execute >/dev/null 2>&1
cp /tmp/takumi-build/out/repro.ark /tmp/takumi-it-repro-b.ark 2>/dev/null
if [ -f /tmp/takumi-it-repro-a.ark ] && cmp -s /tmp/takumi-it-repro-a.ark /tmp/takumi-it-repro-b.ark; then
  echo "  ok   two builds with fixed SOURCE_DATE_EPOCH -> byte-identical .ark"
else
  echo "  FAIL builds not reproducible"
  fails=$((fails + 1))
fi
rm -rf "$RREC" /tmp/takumi-build /tmp/takumi-it-repro-a.ark /tmp/takumi-it-repro-b.ark

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
  # Full-graph build order (v1.0 criterion 5): topologically order the entire
  # corpus as one dependency graph; must succeed with no cycle.
  if "$BIN" order "$ZUGOT" >/tmp/takumi-it-order.txt 2>&1; then
    ocount=$(wc -l < /tmp/takumi-it-order.txt)
    if [ "$ocount" -gt 0 ] && ! grep -qi cycle /tmp/takumi-it-order.txt; then
      echo "  ok   full-graph order over $ocount packages (no cycle)"
    else
      echo "  FAIL order produced no output or reported a cycle"
      fails=$((fails + 1))
    fi
  else
    echo "  FAIL order exited nonzero over the corpus"
    fails=$((fails + 1))
  fi
  rm -f /tmp/takumi-it-order.txt
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
