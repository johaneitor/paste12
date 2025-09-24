#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
mkdir -p "$OUT"
ts="$(date -u +%Y%m%d-%H%M%SZ)"
echo "BASE=$BASE"
curl -fsS "$BASE/api/health" -o "$OUT/health-$ts.json" && echo "health -> $OUT/health-$ts.json" || true
curl -fsS -I -X OPTIONS "$BASE/api/notes" -o "$OUT/options-$ts.txt" && echo "options -> $OUT/options-$ts.txt" || true
curl -fsS -D "$OUT/api-notes-h-$ts.txt" -o "$OUT/api-notes-b-$ts.json" "$BASE/api/notes?limit=5" || true
echo "Archivos en $OUT:"; ls -1 "$OUT" | tail -n 10
