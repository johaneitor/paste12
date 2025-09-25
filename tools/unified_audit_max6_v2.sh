#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"

# salida segura
if [[ ! -d "$OUT" ]] || ! touch "$OUT/.p12" 2>/dev/null; then
  OUT="$HOME/Download"
  mkdir -p "$OUT"
fi

H="$OUT/index-headers-$TS.txt"
I="$OUT/index-$TS.html"
TH="$OUT/terms-headers-$TS.txt"
T="$OUT/terms-$TS.html"
PH="$OUT/privacy-headers-$TS.txt"
P="$OUT/privacy-$TS.html"
NH="$OUT/api-notes-headers-$TS.txt"
NB="$OUT/api-notes-$TS.json"
OH="$OUT/options-$TS.txt"
HH="$OUT/health-$TS.json"
SUM="$OUT/unified-audit-$TS.txt"

curl -sSI "$BASE/" | sed 's/\r$//' > "$H" || true
curl -sS "$BASE/?v=$TS&nosw=1" -o "$I" || true
curl -sSI "$BASE/terms" | sed 's/\r$//' > "$TH" || true
curl -sS "$BASE/terms?v=$TS" -o "$T" || true
curl -sSI "$BASE/privacy" | sed 's/\r$//' > "$PH" || true
curl -sS "$BASE/privacy?v=$TS" -o "$P" || true
curl -sSI -X OPTIONS "$BASE/api/notes" | sed 's/\r$//' > "$OH" || true
curl -sSI "$BASE/api/notes?limit=10" | sed 's/\r$//' > "$NH" || true
curl -sS  "$BASE/api/notes?limit=10" -o "$NB" || true
curl -sS  "$BASE/api/health" -o "$HH" || true

# checks rápidos
ADS_META=$(grep -ci 'google-adsense-account' "$I" || true)
ADS_JS=$(grep -ci 'pagead2.googlesyndication.com/pagead/js/adsbygoogle.js' "$I" || true)
VIEWS_SPAN=$(grep -c 'class="views"' "$I" || true)
INDEX_CODE=$(head -n1 "$H" | awk '{print $2}')

{
  echo "== Unified audit =="
  echo "base: $BASE"
  echo "ts  : $TS"
  echo
  echo "-- health --"
  cat "$HH" 2>/dev/null || true
  echo
  echo "-- OPTIONS /api/notes --"
  cat "$OH" 2>/dev/null || true
  echo
  echo "-- GET /api/notes headers --"
  cat "$NH" 2>/dev/null || true
  echo
  echo "-- GET /api/notes body (primeras 2 líneas) --"
  head -n2 "$NB" 2>/dev/null || true
  echo
  echo "-- index headers (1ra línea) --"
  head -n1 "$H" 2>/dev/null || true
  echo
  echo "-- quick checks --"
  echo "index code: $INDEX_CODE"
  echo "AdSense meta: $ADS_META"
  echo "AdSense script: $ADS_JS"
  echo "span.views: $VIEWS_SPAN"
  echo
  echo "Archivos:"
  echo "  $HH"
  echo "  $OH"
  echo "  $NH"
  echo "  $NB"
  echo "  $H"
  echo "  $I"
  echo "  $TH"
  echo "  $T"
  echo "  $PH"
  echo "  $P"
} > "$SUM"

echo "Guardado resumen: $SUM"
