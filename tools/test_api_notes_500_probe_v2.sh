#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"

mkdir -p "$OUT"

echo "== probe =="
echo "base: $BASE"
echo "-- health --"
curl -fsS "$BASE/api/health" -o "$OUT/health-$TS.json" && cat "$OUT/health-$TS.json" || true
echo

echo "-- OPTIONS /api/notes --"
curl -fsS -D "$OUT/options-$TS.txt" -o /dev/null -X OPTIONS "$BASE/api/notes" || true
tail -n +1 "$OUT/options-$TS.txt" | sed -n '1,20p'

echo
echo "-- GET /api/notes (headers+body) --"
curl -s -D "$OUT/api-notes-headers-$TS.txt" "$BASE/api/notes?limit=10" -o "$OUT/api-notes-$TS.json" || true
head -n 30 "$OUT/api-notes-headers-$TS.txt"
echo
echo "first body line:"
head -n 1 "$OUT/api-notes-$TS.json" || true

echo
echo "-- Link header --"
grep -i '^link:' "$OUT/api-notes-headers-$TS.txt" || echo "NO LINK HEADER"

echo
echo "Files:"
printf "  %s\n" "$OUT/health-$TS.json" "$OUT/options-$TS.txt" "$OUT/api-notes-headers-$TS.txt" "$OUT/api-notes-$TS.json"
