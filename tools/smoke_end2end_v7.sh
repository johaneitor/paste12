#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p "$OUT"

h="$OUT/01-backend-$TS.txt"
p="$OUT/02-preflight-$TS.txt"
a="$OUT/03-api-notes-$TS.txt"
f="$OUT/04-frontend-$TS.txt"
s="$OUT/05-summary-$TS.txt"

# 01 backend
{
  echo "== 01 BACKEND =="; echo "BASE: $BASE"
  echo "-- health headers --"; curl -sSI "$BASE/api/health" | sed -e 's/\r$//'
  echo; echo "-- health body (primera línea) --"; curl -sS "$BASE/api/health" | head -n1
} >"$h"

# 02 preflight
{
  echo "== 02 PREFLIGHT (OPTIONS /api/notes) ==";
  curl -sSI -X OPTIONS "$BASE/api/notes" | sed -e 's/\r$//'
  echo; echo "-- expected headers --"
  echo "Access-Control-Allow-Origin: *"
  echo "Access-Control-Allow-Methods: GET, POST, HEAD, OPTIONS"
  echo "Access-Control-Allow-Headers: Content-Type"
  echo "Access-Control-Max-Age: 86400"
} >"$p"

# 03 api-notes
{
  echo "== 03 API /api/notes ==";
  echo "-- headers --"; curl -sSI "$BASE/api/notes?limit=10" | sed -e 's/\r$//'
  echo; echo "-- body (len + link) --"
  body="$OUT/api-notes-$TS.json"; curl -sS "$BASE/api/notes?limit=10" -o "$body" || true
  test -f "$body" && { wc -c "$body"; head -n1 "$body" | cut -c1-160; }
} >"$a"

# 04 frontend
{
  echo "== 04 FRONTEND ==";
  curl -sSI "$BASE/" | sed -e 's/\r$//'
  idx="$OUT/index-$TS.html"; curl -sS "$BASE/" -o "$idx" || true
  echo; echo "-- quick checks --"
  echo "titles: $(grep -ci '<h1' "$idx" || true)"
  echo "views-span: $(grep -ci 'class=\"views\"' "$idx" || true)"
  echo "ads-meta: $(grep -ci 'google-adsense-account' "$idx" || true)"
  echo "ads-script: $(grep -ci 'pagead2.googlesyndication.com' "$idx" || true)"
} >"$f"

# 05 summary
{
  echo "== 05 SUMMARY ==";
  echo "* health: $(jq -r '.api, .ok, .ver' <(curl -sS "$BASE/api/health") 2>/dev/null | paste -sd, -)"
  echo "* preflight OK? -> $(grep -ci 'Access-Control-Allow-Methods' "$p") header(s) found"
  echo "* api-notes status -> $(grep -m1 -oE '^HTTP/[^\r\n]+' "$a" || echo "n/a")"
  echo "* index quick: $(tail -n4 "$f" | tr '\n' ' ' )"
  echo; echo "Archivos:"
  printf "  %s\n" "$h" "$p" "$a" "$f"
} >"$s"

echo "Listo. Reportes:"
printf "  %s\n" "$h" "$p" "$a" "$f" "$s"
