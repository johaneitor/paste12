#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"

# Salidas (máx. 5 archivos grandes)
F1="$OUT/01-backend-$TS.txt"
F2="$OUT/02-preflight-$TS.txt"
F3="$OUT/03-api-notes-$TS.txt"
F4="$OUT/04-frontend-$TS.txt"
F5="$OUT/05-summary-$TS.txt"

mkdir -p "$OUT"
TMP="$OUT/.tmp-$TS"
mkdir -p "$TMP"

line(){ printf '%s\n' '--------------------------------------------------------------------------------'; }

###############################################################################
# 01) BACKEND (health: headers+body, sin pipes frágiles)
###############################################################################
{
  echo "== 01 BACKEND =="
  echo "BASE: $BASE"
  line
  echo "-- health headers --"
  curl -sS -D "$TMP/health.h" -o "$TMP/health.b" "$BASE/api/health" || true
  sed -n '1,50p' "$TMP/health.h" 2>/dev/null || true
  echo
  echo "-- health body (primera línea) --"
  head -n 1 "$TMP/health.b" 2>/dev/null || true
  echo
  APIFLAG="$(tr -d '\r' < "$TMP/health.b" | grep -o '"api":[^,}]*' || true)"
  echo "api-flag: ${APIFLAG:-<no api flag>}"
} > "$F1"

###############################################################################
# 02) PREFLIGHT (CORS)
###############################################################################
{
  echo "== 02 PREFLIGHT (OPTIONS /api/notes) =="
  curl -sS -i -X OPTIONS "$BASE/api/notes" > "$TMP/preflight.h" || true
  sed -n '1,200p' "$TMP/preflight.h" 2>/dev/null || true
  echo
  echo "-- expected headers --"
  echo "Access-Control-Allow-Origin: *"
  echo "Access-Control-Allow-Methods: GET, POST, HEAD, OPTIONS"
  echo "Access-Control-Allow-Headers: Content-Type"
  echo "Access-Control-Max-Age: 86400"
} > "$F2"

###############################################################################
# 03) API NOTES (status, headers, primer byte del body, Link)
###############################################################################
{
  echo "== 03 /api/notes?limit=10 =="
  echo "-- status+headers --"
  curl -sS -D "$TMP/notes.h" -o "$TMP/notes.b" "$BASE/api/notes?limit=10" || true
  sed -n '1,60p' "$TMP/notes.h" 2>/dev/null || true
  echo
  echo "-- body first line --"
  head -n 1 "$TMP/notes.b" 2>/dev/null || true
  echo
  echo "-- body size (bytes) --"
  wc -c "$TMP/notes.b" 2>/dev/null || true
  echo
  echo "-- Link header --"
  (grep -i '^link:' "$TMP/notes.h" || echo "NO LINK HEADER") 2>/dev/null
} > "$F3"

###############################################################################
# 04) FRONTEND (/, /terms, /privacy) + checks (h1/adsense/views)
###############################################################################
fetch(){ curl -sS -D "$2" -o "$1" -L "$3" || true; }
gcount(){ grep -E -c "$1" "$2" 2>/dev/null || true; }

{
  echo "== 04 FRONTEND =="
  I="$OUT/index-$TS.html";   IH="$TMP/index.h"
  T="$OUT/terms-$TS.html";   TH="$TMP/terms.h"
  P="$OUT/privacy-$TS.html"; PH="$TMP/privacy.h"

  echo "-- GET / (save html+headers) --"
  fetch "$I" "$IH" "$BASE/"
  sed -n '1,20p' "$IH" 2>/dev/null || true
  echo

  echo "-- GET /terms --"
  fetch "$T" "$TH" "$BASE/terms"
  sed -n '1,20p' "$TH" 2>/dev/null || true
  echo

  echo "-- GET /privacy --"
  fetch "$P" "$PH" "$BASE/privacy"
  sed -n '1,20p' "$PH" 2>/dev/null || true
  echo

  echo "-- checks on / --"
  H1S=$(gcount '<h1(\s|>)' "$I")
  ADS_META=$(gcount '<meta[^>]+name=["'"'"']google-adsense-account["'"'"']' "$I")
  ADS_JS=$(gcount 'pagead/js/adsbygoogle\.js\?client=' "$I")
  VIEWS=$(gcount 'class=["'"'"'][^"'"'"'>]*\bviews\b' "$I")
  echo "h1_count=$H1S ads_meta=$ADS_META ads_script=$ADS_JS views_span=$VIEWS"
} > "$F4"

###############################################################################
# 05) SUMMARY (diagnóstico compactado a prueba de regresiones)
###############################################################################
{
  echo "== 05 SUMMARY =="
  echo "BASE: $BASE"
  echo

  echo "[backend]"
  (grep -m1 -E '^HTTP/|^http/' "$TMP/health.h" || true) 2>/dev/null
  APIF="$(grep -o '"api":[^,}]*' "$TMP/health.b" 2>/dev/null || true)"
  echo "health.$APIF"
  echo

  echo "[preflight]"
  for h in 'Access-Control-Allow-Origin' \
           'Access-Control-Allow-Methods' \
           'Access-Control-Allow-Headers' \
           'Access-Control-Max-Age'
  do
    if grep -qi "^$h:" "$TMP/preflight.h"; then
      echo "OK: $h"
    else
      echo "WARN: falta $h"
    fi
  done
  echo

  echo "[api-notes]"
  if grep -qi '^HTTP/2 500' "$TMP/notes.h"; then
    echo "ERROR: GET /api/notes -> 500 (runtime)"
  elif grep -qi '^HTTP/2 404' "$TMP/notes.h"; then
    echo "ERROR: GET /api/notes -> 404 (ruta no montada)"
  else
    echo "OK/VER: revisar Link header"
    grep -i '^link:' "$TMP/notes.h" || echo "NO LINK HEADER"
  fi
  echo

  echo "[frontend /]"
  LINE=$(grep -m1 'h1_count=' "$F4" || true)
  echo "$LINE"
  echo "Expectativas: h1_count=1 ads_meta>=1 ads_script>=1 views_span=1"
  echo

  echo "[archivos]"
  printf '  %s\n' "$F1" "$F2" "$F3" "$F4" "$F5"
} > "$F5"

echo "Guardados:"
printf '  %s\n' "$F1" "$F2" "$F3" "$F4" "$F5"
