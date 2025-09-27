#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p "$OUT"

echo "== SMOKE API/CORS v1 =="
curl -fsS "$BASE/api/health" -o "$OUT/health-$TS.json" && cat "$OUT/health-$TS.json" || true
echo

echo "-- OPTIONS /api/notes --"
curl -i -sS -X OPTIONS "$BASE/api/notes" | tee "$OUT/options-$TS.txt" >/dev/null

echo "-- GET /api/notes --"
curl -i -sS "$BASE/api/notes?limit=10" | tee "$OUT/api-notes-h-$TS.txt" >/dev/null
curl -sS  "$BASE/api/notes?limit=10" -o "$OUT/api-notes-$TS.json" || true
head -n1 "$OUT/api-notes-$TS.json" 2>/dev/null || true

echo "-- QUICK CHECKS --"
H="$(awk 'BEGIN{IGNORECASE=1}/Access-Control-Allow-Headers/{print;f=1}END{if(!f)print "NO Access-Control-Allow-Headers"}' "$OUT/options-$TS.txt")"
M="$(awk 'BEGIN{IGNORECASE=1}/Access-Control-Allow-Methods/{print;f=1}END{if(!f)print "NO Access-Control-Allow-Methods"}' "$OUT/options-$TS.txt")"
O="$(awk 'BEGIN{IGNORECASE=1}/Access-Control-Allow-Origin/{print;f=1}END{if(!f)print "NO Access-Control-Allow-Origin"}' "$OUT/options-$TS.txt")"
echo "$H"; echo "$M"; echo "$O"

echo "Archivos:"
echo "  $OUT/health-$TS.json"
echo "  $OUT/options-$TS.txt"
echo "  $OUT/api-notes-h-$TS.txt"
echo "  $OUT/api-notes-$TS.json"
