#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL OUTDIR}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"

mkdir -p "$OUT"

curl -sS "$BASE/api/health" -o "$OUT/health-$TS.json"
curl -i -X OPTIONS "$BASE/api/notes" -o "$OUT/options-$TS.txt" || true

# index / terms / privacy
curl -sS "$BASE/" -o "$OUT/index-$TS.html"
curl -i -sS "$BASE/" | head -50 > "$OUT/index-headers-$TS.txt"

curl -sS "$BASE/terms" -o "$OUT/terms-$TS.html"
curl -i -sS "$BASE/terms" | head -50 > "$OUT/terms-headers-$TS.txt" || true

curl -sS "$BASE/privacy" -o "$OUT/privacy-$TS.html"
curl -i -sS "$BASE/privacy" | head -50 > "$OUT/privacy-headers-$TS.txt" || true

# /api/notes GET (headers + body si 200)
code=$(curl -sS -o "$OUT/api-notes-$TS.json" -w "%{http_code}" "$BASE/api/notes?limit=10" || true)
curl -i -sS "$BASE/api/notes?limit=10" | head -50 > "$OUT/api-notes-headers-$TS.txt" || true

# Chequeos rápidos (AdSense + .views)
ADS=$([ -n "$(grep -i 'google-adsense-account' "$OUT/index-$TS.html" || true)" ] && echo OK || echo FAIL)
VW=$([ -n "$(grep -i 'class=\"views\"' "$OUT/index-$TS.html" || true)" ] && echo OK || echo FAIL)

{
  echo "== Unified audit (frontlock) =="
  echo "base: $BASE"
  echo "ts  : $TS"
  echo "-- health --"
  cat "$OUT/health-$TS.json" 2>/dev/null || true
  echo
  echo "-- OPTIONS /api/notes --"
  head -20 "$OUT/options-$TS.txt" 2>/dev/null || true
  echo
  echo "-- GET /api/notes (headers) --"
  head -20 "$OUT/api-notes-headers-$TS.txt" 2>/dev/null || true
  echo
  echo "-- index checks --"
  echo "AdSense meta: $ADS"
  echo "span.views  : $VW"
  echo
  echo "Archivos:"
  echo "  $OUT/health-$TS.json"
  echo "  $OUT/options-$TS.txt"
  echo "  $OUT/api-notes-headers-$TS.txt"
  echo "  $OUT/api-notes-$TS.json (code=$code)"
  echo "  $OUT/index-$TS.html"
  echo "  $OUT/index-headers-$TS.txt"
  echo "  $OUT/terms-$TS.html"
  echo "  $OUT/terms-headers-$TS.txt"
  echo "  $OUT/privacy-$TS.html"
  echo "  $OUT/privacy-headers-$TS.txt"
  echo "== END =="
} > "$OUT/unified-audit-$TS.txt"

echo "Reporte: $OUT/unified-audit-$TS.txt"
