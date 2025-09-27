#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"

F1="$OUT/01-backend-$TS.txt"
F2="$OUT/02-preflight-$TS.txt"
F3="$OUT/03-api-notes-$TS.txt"
F4="$OUT/04-frontend-$TS.txt"
F5="$OUT/05-summary-$TS.txt"

mkdir -p "$OUT"

line() { printf '%s\n' "--------------------------------------------------------------------------------"; }

# 01) BACKEND (health + lectura rápida)
{
  echo "== 01 BACKEND =="
  echo "BASE: $BASE"
  line
  echo "-- health (status + body) --"
  curl -sS -D - -o /tmp/h.$$ "$BASE/api/health" || true
  head -n 20 /tmp/h.$$
  echo
  BODY="$(cat /tmp/h.$$)"
  echo "$BODY" | tr -d '\r' | sed -n '1,200p' >/dev/null
  API_FLAG="$(printf '%s' "$BODY" | grep -o '"api":[^,]*' || true)"
  echo "api-flag: ${API_FLAG:-<no api key found>}"
  rm -f /tmp/h.$$
} > "$F1"

# 02) PREFLIGHT (CORS)
{
  echo "== 02 PREFLIGHT =="
  echo "-- OPTIONS /api/notes headers --"
  curl -sS -i -X OPTIONS "$BASE/api/notes" | sed -n '1,200p'
  echo
  echo "-- expected headers --"
  echo "Access-Control-Allow-Origin: *"
  echo "Access-Control-Allow-Methods: GET, POST, HEAD, OPTIONS"
  echo "Access-Control-Allow-Headers: Content-Type"
  echo "Access-Control-Max-Age: 86400"
} > "$F2"

# 03) API NOTES (headers + primera línea body + Link)
{
  echo "== 03 API /api/notes =="
  echo "-- headers --"
  curl -sS -i "$BASE/api/notes?limit=10" -o /tmp/n.$$ | sed -n '1,60p' || true
  echo
  echo "-- first body line --"
  head -n1 /tmp/n.$$ || true
  echo
  echo "-- body size (bytes) --"
  wc -c /tmp/n.$$ 2>/dev/null || true
  echo
  echo "-- Link header --"
  curl -sS -I "$BASE/api/notes?limit=10" 2>/dev/null | grep -i '^link:' || echo "NO LINK HEADER"
  rm -f /tmp/n.$$
} > "$F3"

# 04) FRONTEND (index/terms/privacy + Adsense + views + H1)
fetch_html() { curl -sS "$1" -o "$2" -D "$3" -L; }
grep_count() { grep -E -c "$1" "$2" 2>/dev/null || true; }

{
  echo "== 04 FRONTEND =="
  I="$OUT/index-$TS.html"; IH="$OUT/index-h-$TS.txt"
  T="$OUT/terms-$TS.html"; TH="$OUT/terms-h-$TS.txt"
  P="$OUT/privacy-$TS.html"; PH="$OUT/privacy-h-$TS.txt"

  echo "-- GET / (save html+headers) --"
  fetch_html "$BASE/" "$I" "$IH" || true
  head -n 20 "$IH" 2>/dev/null || true
  echo

  echo "-- GET /terms --"
  fetch_html "$BASE/terms" "$T" "$TH" || true
  head -n 20 "$TH" 2>/dev/null || true
  echo

  echo "-- GET /privacy --"
  fetch_html "$BASE/privacy" "$P" "$PH" || true
  head -n 20 "$PH" 2>/dev/null || true
  echo

  echo "-- checks on / --"
  H1S=$(grep_count '<h1' "$I")
  ADS_META=$(grep_count '<meta[^>]+name=["'\'']google-adsense-account["'\'']' "$I")
  ADS_JS=$(grep_count 'pagead/js/adsbygoogle.js\?client=' "$I")
  VIEWS=$(grep_count 'class=["'\''][^"'\''>]*\bviews\b' "$I")
  echo "h1_count=$H1S, ads_meta=$ADS_META, ads_script=$ADS_JS, views_span=$VIEWS"
} > "$F4"

# 05) SUMMARY (diagnóstico compacto)
{
  echo "== 05 SUMMARY =="
  echo "BASE: $BASE"
  echo
  echo "[backend]"
  APIFLAG="$(grep -o '"api":[^,}]*' "$F1" | head -n1 || true)"
  echo "health.$APIFLAG"
  if ! grep -qi 'Access-Control-Allow-Methods:' "$F2"; then
    echo "WARN: Falta Access-Control-Allow-Methods en preflight"
  fi
  if ! grep -qi 'Access-Control-Allow-Headers:' "$F2"; then
    echo "WARN: Falta Access-Control-Allow-Headers en preflight"
  fi

  echo
  echo "[api]"
  if grep -qi '^HTTP/2 500' "$F3"; then
    echo "ERROR: GET /api/notes -> 500 (runtime)"
  elif grep -qi '^HTTP/2 404' "$F3"; then
    echo "ERROR: GET /api/notes -> 404 (ruta no montada)"
  else
    echo "OK/VER: revisar encabezados y Link:"
    grep -i '^link:' "$F3" || echo "NO LINK HEADER"
  fi

  echo
  echo "[frontend]"
  if grep -q 'h1_count=1' "$F4"; then echo "OK: un solo <h1>"; else echo "WARN: h1 duplicado o faltante"; fi
  if grep -q 'ads_meta=1' "$F4"; then echo "OK: meta AdSense"; else echo "WARN: falta meta AdSense"; fi
  if grep -q 'ads_script=1' "$F4"; then echo "OK: script AdSense"; else echo "WARN: falta script AdSense"; fi
  if grep -q 'views_span=1' "$F4"; then echo "OK: span .views"; else echo "WARN: falta span .views"; fi

  echo
  echo "[archivos]"
  printf '  %s\n' "$F1" "$F2" "$F3" "$F4" "$F5"
} > "$F5"

echo "Guardados:"
printf '  %s\n' "$F1" "$F2" "$F3" "$F4" "$F5"
