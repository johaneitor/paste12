#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p "$OUT"

echo "BASE=$BASE"
echo "→ health"
curl -sS "$BASE/api/health" -o "$OUT/health-$TS.json" || true
cat "$OUT/health-$TS.json" 2>/dev/null || true

echo "→ OPTIONS /api/notes (headers)"
curl -sS -D "$OUT/options-$TS.txt" -o /dev/null -X OPTIONS "$BASE/api/notes" || true
tail -n +1 "$OUT/options-$TS.txt" | sed -n '1,12p' || true

echo "→ GET /api/notes (headers + body)"
curl -sS -D "$OUT/api-notes-h-$TS.txt" -o "$OUT/api-notes-$TS.json" "$BASE/api/notes?limit=10" || true
head -c 200 "$OUT/api-notes-$TS.json" 2>/dev/null || echo "(sin body)"

echo "→ index (para AdSense/views)"
curl -sS -D "$OUT/index-headers-$TS.txt" -o "$OUT/index-$TS.html" "$BASE/?debug=1&nosw=1&v=$RANDOM" || true

echo "== Archivos =="
printf "  %s\n" \
  "$OUT/health-$TS.json" \
  "$OUT/options-$TS.txt" \
  "$OUT/api-notes-h-$TS.txt" \
  "$OUT/api-notes-$TS.json" \
  "$OUT/index-headers-$TS.txt" \
  "$OUT/index-$TS.html"

echo "Hecho."
