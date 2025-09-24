#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: BASE OUTDIR}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p "$OUT"

curl -sS "$BASE/?nosw=1&v=$(date +%s)" -o "$OUT/index-live-$TS.html"
cp -f frontend/index.html "$OUT/index-local-$TS.html"

python - <<PY
import hashlib, io, sys
live = io.open("$OUT/index-live-$TS.html","rb").read()
loc  = io.open("$OUT/index-local-$TS.html","rb").read()
def h(x): return hashlib.sha256(x).hexdigest()
print("sha live:", h(live))
print("sha loc :", h(loc))
PY

# Checks
echo "-- checks en remoto --"
grep -q 'class="views"' "$OUT/index-live-$TS.html" && echo "OK  - views span (.views)" || echo "FAIL- views span (.views)"
grep -qi 'pagead2.googlesyndication.com/pagead/js/adsbygoogle.js' "$OUT/index-live-$TS.html" && echo "OK  - AdSense presente" || echo "FAIL- AdSense presente"

echo "-- checks en local --"
grep -q 'class="views"' "$OUT/index-local-$TS.html" && echo "OK  - views span (.views)" || echo "FAIL- views span (.views)"
grep -qi 'pagead2.googlesyndication.com/pagead/js/adsbygoogle.js' "$OUT/index-local-$TS.html" && echo "OK  - AdSense presente" || echo "FAIL- AdSense presente"

echo "OK: /sdcard/Download/index-live-$TS.html"
echo "OK: /sdcard/Download/index-local-$TS.html"
