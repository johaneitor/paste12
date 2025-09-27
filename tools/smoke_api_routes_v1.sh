#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p "$OUT"

echo "== SMOKE api =="
curl -fsS "$BASE/api/health" -o "$OUT/health-$TS.json" && cat "$OUT/health-$TS.json" || true
echo
echo "-- OPTIONS /api/notes --"
curl -isS -X OPTIONS "$BASE/api/notes" | tee "$OUT/options-$TS.txt" >/dev/null || true
echo "-- GET /api/notes --"
curl -isS "$BASE/api/notes?limit=10" | tee "$OUT/api-notes-h-$TS.txt" >/dev/null | head -n1 || true
echo "-- Link header --"
grep -i '^link:' "$OUT/api-notes-h-$TS.txt" || echo "NO LINK"
echo "Archivos:"
echo "  $OUT/health-$TS.json"
echo "  $OUT/options-$TS.txt"
echo "  $OUT/api-notes-h-$TS.txt"
