#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p "$OUT"

echo "== SMOKE =="
curl -sS "$BASE/api/health" | tee "$OUT/health-$TS.json"
echo
echo "-- OPTIONS /api/notes --"
curl -sS -i -X OPTIONS "$BASE/api/notes" | tee "$OUT/options-$TS.txt" >/dev/null
echo
echo "-- GET /api/notes --"
curl -sS -i "$BASE/api/notes?limit=10" | tee "$OUT/api-notes-h-$TS.txt" >/dev/null
curl -sS "$BASE/api/notes?limit=10" | tee "$OUT/api-notes-$TS.json" >/dev/null
echo
echo "Archivos:"
printf "  %s\n" "$OUT/health-$TS.json" "$OUT/options-$TS.txt" "$OUT/api-notes-h-$TS.txt" "$OUT/api-notes-$TS.json"
