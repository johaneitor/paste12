#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"

mkdir -p "$OUT"

echo "== SMOKE CORE =="
curl -sS "$BASE/api/health" | tee "$OUT/health-$TS.json"; echo

echo "-- OPTIONS /api/notes --"
curl -i -sS -X OPTIONS "$BASE/api/notes" | tee "$OUT/options-$TS.txt" >/dev/null

echo "-- GET /api/notes (headers) --"
curl -i -sS "$BASE/api/notes?limit=10" | tee "$OUT/api-notes-headers-$TS.txt" >/dev/null || true

echo "-- GET /api/notes (body) --"
curl -sS "$BASE/api/notes?limit=10" -o "$OUT/api-notes-$TS.json" || true
head -n 1 "$OUT/api-notes-$TS.json" 2>/dev/null || echo "(sin cuerpo)"

echo "-- INDEX --"
curl -i -sS "$BASE/" | tee "$OUT/index-headers-$TS.txt" >/dev/null
curl -sS "$BASE/" -o "$OUT/index-$TS.html" || true

echo "== RESUMEN =="
echo "Archivos:"
printf "  %s\n" \
 "$OUT/health-$TS.json" \
 "$OUT/options-$TS.txt" \
 "$OUT/api-notes-headers-$TS.txt" \
 "$OUT/api-notes-$TS.json" \
 "$OUT/index-headers-$TS.txt" \
 "$OUT/index-$TS.html"
