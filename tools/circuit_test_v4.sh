#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="/sdcard/Download"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
h="$OUT/01-backend-$TS.txt"
p="$OUT/02-preflight-$TS.txt"
a="$OUT/03-api-notes-$TS.txt"
f="$OUT/04-frontend-$TS.txt"
s="$OUT/05-summary-$TS.txt"

# 01 - backend/health
{
  echo "== 01 BACKEND =="; echo "BASE: $BASE"
  echo "-- health headers --"
  curl -sSI "$BASE/api/health"
  echo; echo "-- health body (primera línea) --"
  curl -sS "$BASE/api/health" | head -n1
} > "$h"

# 02 - preflight OPTIONS (forzamos headers esperados)
{
  echo "== 02 PREFLIGHT (OPTIONS /api/notes) =="
  curl -sSI -X OPTIONS \
    -H 'Access-Control-Request-Method: GET' \
    -H 'Origin: https://example.org' \
    "$BASE/api/notes"
  echo
  echo "-- expected headers --"
  echo "Access-Control-Allow-Origin: *"
  echo "Access-Control-Allow-Methods: GET, POST, HEAD, OPTIONS"
  echo "Access-Control-Allow-Headers: Content-Type"
  echo "Access-Control-Max-Age: 86400"
} > "$p"

# 03 - GET /api/notes
{
  echo "== 03 API NOTES =="
  echo "-- headers --"
  curl -sSI "$BASE/api/notes"
  echo; echo "-- body (len) --"
  body="/sdcard/Download/api-notes-$TS.json"
  curl -sS "$BASE/api/notes" -o "$body" || true
  [ -f "$body" ] && echo "$(wc -c < "$body") $body" || echo "N/A"
} > "$a"

# 04 - Frontend: checks básicos (código, ads, views)
{
  echo "== 04 FRONTEND =="
  idx="$OUT/index-$TS.html"; ih="$OUT/index-headers-$TS.txt"
  curl -sSI "$BASE/" | tee "$ih"
  curl -sS "$BASE/" -o "$idx" || true
  code=$(sed -n '1p' "$ih" | awk '{print $2}')
  echo "-- quick checks --"
  echo "index code: $code"
  ads_meta=$(grep -c -i '<meta[^>]*name=["'\'']google-adsense-account["'\'']' "$idx" || true)
  ads_script=$(grep -c -i 'adsbygoogle\.js' "$idx" || true)
  views_span=$(grep -c -i 'class=["'\''][^"'\'']*views' "$idx" || true)
  echo "ads_meta=$ads_meta"
  echo "ads_script=$ads_script"
  echo "views_span=$views_span"
} > "$f"

# 05 - Summary
{
  echo "== 05 SUMMARY =="; echo "BASE: $BASE"; echo
  echo "[backend]"; head -n 1 "$h"; grep -m1 '"api":' "$h" || true; echo
  echo "[preflight]"; grep -i 'access-control-allow-' "$p" || true; echo
  echo "[api-notes]"; grep -m1 '^HTTP/' "$a" || true; echo
  echo "[frontend /]"; grep -E 'ads_meta=|ads_script=|views_span=|index code:' "$f" || true; echo
  echo "[archivos]"; printf "  %s\n" "$h" "$p" "$a" "$f" "$s"
} > "$s"

echo "Hecho. Reportes:"
printf "  %s\n" "$h" "$p" "$a" "$f" "$s"
