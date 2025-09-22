#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"
OUT="${2:-/sdcard/Download}"
[ -z "$BASE" ] && { echo "Uso: $0 https://host [/sdcard/Download]"; exit 1; }
mkdir -p "$OUT"
now="$(date -u +%Y%m%d-%H%M%SZ)"

BE="$OUT/backend-audit-$now.txt"
FE="$OUT/frontend-audit-$now.txt"
IX="$OUT/index-$now.html"

# Backend audit
{
  echo "base: $BASE"
  echo "== /api/health =="; curl -fsS "$BASE/api/health"; echo; echo
  echo "== OPTIONS /api/notes =="; curl -fsS -i -X OPTIONS "$BASE/api/notes"; echo
  echo "== GET /api/notes?limit=10 =="; curl -fsS -i "$BASE/api/notes?limit=10"; echo
  echo "== NEGATIVOS: like/view/report 999999 =="; 
  for a in like view report; do
    code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/api/notes/999999/$a")"
    echo "$a   -> $code"
  done
} > "$BE"
echo "OK: $BE"

# Frontend audit
curl -fsS "$BASE" -o "$IX"
bytes="$(wc -c < "$IX" | tr -d ' ')"
{
  echo "== FE: index (sin SW) =="
  echo "bytes=$bytes"
  echo
  echo "== Primeros 64 bytes =="
  head -c 64 "$IX" | od -An -t x1
} > "$FE"
echo "OK: $IX"
echo "OK: $FE"
