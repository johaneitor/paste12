#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p "$OUT"
echo "== publish contract =="
echo "[BASE] $BASE"

echo "-- OPTIONS /api/notes --"
curl -sS -i -X OPTIONS "$BASE/api/notes" | tee "$OUT/options-$TS.txt" >/dev/null

echo "-- POST JSON /api/notes --"
curl -sS -i -H 'Content-Type: application/json' -d '{"text":"contract json '"$TS"'"}' \
  "$BASE/api/notes" | tee "$OUT/post-json-h-$TS.txt" >/dev/null

echo "-- POST FORM /api/notes --"
curl -sS -i -F 'text=contract form '"$TS"'' \
  "$BASE/api/notes" | tee "$OUT/post-form-h-$TS.txt" >/dev/null

echo "-- GET /api/notes --"
curl -sS -i "$BASE/api/notes?limit=5" | tee "$OUT/get-notes-h-$TS.txt" >/dev/null

echo "-- Negative like/view/report --"
for p in like view report; do
  curl -sS -i -X POST "$BASE/api/notes/999999/$p" | tee "$OUT/neg-$p-h-$TS.txt" >/dev/null
done

echo "Archivos en $OUT con sufijo $TS"
