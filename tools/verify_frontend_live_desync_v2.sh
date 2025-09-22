#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
TS=$(date -u +%Y%m%d-%H%M%SZ)
mkdir -p "$OUT"

# NOCACHE
V=$(date +%s)
NC="$BASE/?debug=1&nosw=1&v=$V"
LIVE="$OUT/index-live-$TS.html"
LOC="$OUT/index-local-$TS.html"

curl -fsSL "$NC" -o "$LIVE"
cp ./frontend/index.html "$LOC" 2>/dev/null || cp ./index.html "$LOC"

sha_live=$(sha256sum "$LIVE" | awk '{print $1}')
sha_loc=$(sha256sum "$LOC" | awk '{print $1}')

echo "live: $LIVE"
echo "loc : $LOC"
echo "sha live: $sha_live"
echo "sha loc : $sha_loc"
[[ "$sha_live" == "$sha_loc" ]] && echo "OK  - HTML idéntico" || echo "WARN- HTML distinto"

grep -q '<span class="views"' "$LIVE" && echo "OK  - views span (live)" || echo "FAIL- views span (live)"
grep -q 'adsbygoogle.js?client=ca-pub-' "$LIVE" && echo "OK  - AdSense (live)" || echo "WARN- AdSense ausente (live)"

echo "OK: artefactos en $OUT"
