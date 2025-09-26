#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p "$OUT"

echo "== SMOKE =="
curl -sS "$BASE/api/health" | tee "$OUT/health-$TS.json"; echo
curl -sSI -X OPTIONS "$BASE/api/notes" | tee "$OUT/options-$TS.txt" >/dev/null
curl -sSI "$BASE/api/notes?limit=10" | tee "$OUT/api-notes-h-$TS.txt" >/dev/null || true
curl -sS "$BASE/api/notes?limit=10" -o "$OUT/api-notes-$TS.json" || true

# Front quick checks
curl -sS "$BASE" -o "$OUT/index-$TS.html" || true
{
  echo "-- index headers --"
  curl -sSI "$BASE"
} | tee "$OUT/index-headers-$TS.txt" >/dev/null

# Quick greps (AdSense + views span)
ADS_META=$(grep -c 'meta name="google-adsense-account"' "$OUT/index-$TS.html" || true)
ADS_JS=$(grep -c 'pagead2.googlesyndication.com/pagead/js/adsbygoogle.js' "$OUT/index-$TS.html" || true)
VIEWS=$(grep -c 'class="views"' "$OUT/index-$TS.html" || true)
echo "index checks: ads-meta=$ADS_META ads-js=$ADS_JS views-span=$VIEWS" | tee "$OUT/quick-$TS.txt" >/dev/null

echo "Archivos:"
ls -1 "$OUT"/{health-$TS.json,options-$TS.txt,api-notes-h-$TS.txt,api-notes-$TS.json,index-headers-$TS.txt,index-$TS.html,quick-$TS.txt} 2>/dev/null || true
