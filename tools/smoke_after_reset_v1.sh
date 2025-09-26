#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p "$OUT"
echo "== SMOKE after reset =="
curl -sS "$BASE/api/health" | tee "$OUT/health-$TS.json"; echo
echo "-- OPTIONS /api/notes --"
curl -sSi -X OPTIONS "$BASE/api/notes" | tee "$OUT/options-$TS.txt" >/dev/null
echo "-- GET /api/notes --"
curl -sSi "$BASE/api/notes?limit=10" | tee "$OUT/api-notes-h-$TS.txt" >/dev/null
curl -sS "$BASE/api/notes?limit=10" -o "$OUT/api-notes-$TS.json" || true
echo "-- INDEX --"
curl -sSi "$BASE/" | tee "$OUT/index-h-$TS.txt" >/dev/null
curl -sS "$BASE/" -o "$OUT/index-$TS.html" || true
echo "Archivos:"
ls -1 "$OUT"/{health-$TS.json,options-$TS.txt,api-notes-h-$TS.txt,api-notes-$TS.json,index-h-$TS.txt,index-$TS.html} 2>/dev/null || true
