#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUTDIR="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"

h="$OUTDIR/01-backend-$TS.txt"
p="$OUTDIR/02-preflight-$TS.txt"
a="$OUTDIR/03-api-notes-$TS.txt"
f="$OUTDIR/04-frontend-$TS.txt"
s="$OUTDIR/05-summary-$TS.txt"

mkdir -p "$OUTDIR"

# 01 BACKEND
{
  echo "== 01 BACKEND =="; echo "BASE: $BASE"
  echo "-- health headers --"; curl -sSI "$BASE/api/health"
  echo; echo "-- health body (primera línea) --"; curl -sS "$BASE/api/health" | head -n1
} > "$h"

# 02 PREFLIGHT
{
  echo "== 02 PREFLIGHT (OPTIONS /api/notes) ==";
  curl -sSI -X OPTIONS "$BASE/api/notes"
  echo; echo "-- expected headers --"
  echo "Access-Control-Allow-Origin: *"
  echo "Access-Control-Allow-Methods: GET, POST, HEAD, OPTIONS"
  echo "Access-Control-Allow-Headers: Content-Type"
  echo "Access-Control-Max-Age: 86400"
} > "$p"

# 03 API NOTES
J="$OUTDIR/api-notes-$TS.json"
{
  echo "== 03 API NOTES =="
  echo "-- headers --"; curl -sSI "$BASE/api/notes?limit=10"
  echo; echo "-- body (len) --"
  curl -sS "$BASE/api/notes?limit=10" -o "$J" || true
  [[ -f "$J" ]] && wc -c "$J" || echo "no body"
} > "$a"

# 04 FRONTEND
I="$OUTDIR/index-$TS.html"
{
  echo "== 04 FRONTEND =="
  curl -sS "$BASE/" -o "$I" || true
  echo "-- quick checks --"
  [[ -f "$I" ]] && echo "index code: OK" || echo "index: FAIL"
  if [[ -f "$I" ]]; then
    # adsense meta / script + span.views
    grep -qi 'google-adsense-account' "$I" && echo "OK - AdSense meta" || echo "FAIL - AdSense meta"
    grep -qi 'pagead/js/adsbygoogle.js' "$I" && echo "OK - AdSense script" || echo "FAIL - AdSense script"
    grep -qi 'class="views"' "$I" && echo "OK - span.views" || echo "FAIL - span.views"
    # duplicado de títulos h1/h2
    H1=$(grep -io "<h1[^>]*>" "$I" | wc -l | tr -d ' ')
    H2=$(grep -io "<h2[^>]*>" "$I" | wc -l | tr -d ' ')
    echo "H1:$H1 H2:$H2"
  fi
} > "$f"

# 05 RESUMEN
{
  echo "== 05 SUMMARY ==";
  HE=$(curl -sS "$BASE/api/health" | tr -d '\n')
  echo "health: $HE"
  echo "files:"
  echo "  $h"
  echo "  $p"
  echo "  $a"
  echo "  $f"
  [[ -f "$J" ]] && echo "  $J"
} > "$s"

echo "Guardados:"
printf "%s\n%s\n%s\n%s\n%s\n" "$h" "$p" "$a" "$f" "$s"
