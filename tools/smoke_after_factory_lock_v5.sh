#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p "$OUT"

echo "== SMOKE v5 =="
curl -sS "$BASE/api/health" | tee "$OUT/health-$TS.json" | jq . || true

echo "-- OPTIONS /api/notes --"
curl -isS -X OPTIONS "$BASE/api/notes" | tee "$OUT/options-$TS.txt" >/dev/null

echo "-- GET /api/notes --"
curl -isS "$BASE/api/notes?limit=10" | tee "$OUT/api-notes-h-$TS.txt" >/dev/null
curl -sS "$BASE/api/notes?limit=10" -o "$OUT/api-notes-$TS.json" || true
head -c 160 "$OUT/api-notes-$TS.json" 2>/dev/null || true
echo
echo "Archivos:"
ls -1 "$OUT"/health-"$TS".json "$OUT"/options-"$TS".txt "$OUT"/api-notes-*"$TS"* 2>/dev/null || true
