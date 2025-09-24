#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: BASE OUTDIR}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p "$OUT"

echo "== Smoke & Audit =="
curl -sS "$BASE/api/health" -o "$OUT/health-$TS.json"
curl -sSI -X OPTIONS "$BASE/api/notes" -o "$OUT/options-$TS.txt" || true

# GET /api/notes (si falla, guardar headers igualmente)
curl -sSI "$BASE/api/notes?limit=10" -o "$OUT/api-notes-headers-$TS.txt" || true
curl -sS "$BASE/api/notes?limit=10" -o "$OUT/api-notes-$TS.json" || true

# HTML principal + legales (cache bust + sin SW)
for path in "" "terms" "privacy"; do
  url="$BASE/${path}?nosw=1&v=$(date +%s)"
  tag="${path:-index}"
  curl -sS "$url" -o "$OUT/${tag}-$TS.html" || true
  curl -sSI "$url" -o "$OUT/${tag}-headers-$TS.txt" || true
done

# Resumen
{
  echo "== Unified audit =="
  echo "base: $BASE"
  echo "ts  : $TS"
  echo "-- health --"; cat "$OUT/health-$TS.json" 2>/dev/null || true
  echo; echo "-- OPTIONS /api/notes --"; cat "$OUT/options-$TS.txt" 2>/dev/null || true
  echo; echo "-- GET /api/notes (headers) --"; cat "$OUT/api-notes-headers-$TS.txt" 2>/dev/null || true
  echo; echo "-- GET /api/notes (body, first line) --"; head -n1 "$OUT/api-notes-$TS.json" 2>/dev/null || echo "(sin body)"
  echo; echo "-- index checks --"
  if grep -qi 'google-adsense-account' "$OUT/index-$TS.html"; then echo "OK  - AdSense meta"; else echo "FAIL- AdSense meta"; fi
  if grep -qi 'pagead2.googlesyndication.com/pagead/js/adsbygoogle.js' "$OUT/index-$TS.html"; then echo "OK  - AdSense script"; else echo "FAIL- AdSense script"; fi
  if grep -q 'class="views"' "$OUT/index-$TS.html"; then echo "OK  - views span"; else echo "FAIL- views span"; fi
} > "$OUT/unified-audit-$TS.txt"

echo "Guardado: $OUT/unified-audit-$TS.txt"
