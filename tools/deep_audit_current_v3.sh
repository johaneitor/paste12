#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p "$OUT"

IDX="$OUT/index-$TS.html"
HDX="$OUT/index-headers-$TS.txt"
OPT="$OUT/options-$TS.txt"
HNT="$OUT/api-notes-headers-$TS.txt"
BNT="$OUT/api-notes-$TS.json"

# 1) INDEX: HTML + headers
curl -sS -D "$HDX" -o "$IDX" "$BASE/" || true

# 2) OPTIONS /api/notes
curl -sS -D "$OPT" -o /dev/null -X OPTIONS "$BASE/api/notes" || true

# 3) GET /api/notes (headers + body)
curl -sS -D "$HNT" -o "$BNT" "$BASE/api/notes?limit=10" || true

# Informe resumen en STDOUT
echo "== Deep audit (5 archivos) =="
echo "base: $BASE"
echo "ts  : $TS"
echo "-- index headers --"
head -n 20 "$HDX" || true
echo "-- options --"
head -n 20 "$OPT" || true
echo "-- /api/notes headers --"
head -n 20 "$HNT" || true
echo "== Guardados =="
printf "  %s\n" "$IDX" "$HDX" "$OPT" "$HNT" "$BNT"
