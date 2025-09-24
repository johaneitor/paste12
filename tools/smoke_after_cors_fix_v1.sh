#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL}"; OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"

mkdir -p "$OUT"

echo "health -> $OUT/health-$TS.json"
curl -fsS "$BASE/api/health" -o "$OUT/health-$TS.json" || true
jq -r '.' "$OUT/health-$TS.json" 2>/dev/null || cat "$OUT/health-$TS.json" || true

echo "options -> $OUT/options-$TS.txt"
curl -sS -D - -o /dev/null -X OPTIONS "$BASE/api/notes" > "$OUT/options-$TS.txt" || true
head -n 20 "$OUT/options-$TS.txt" || true

echo "GET /api/notes headers -> $OUT/api-notes-h-$TS.txt"
curl -sS -D - -o "$OUT/api-notes-$TS.json" "$BASE/api/notes?limit=1" > "$OUT/api-notes-h-$TS.txt" || true
head -n 1 "$OUT/api-notes-h-$TS.txt" || true
test -s "$OUT/api-notes-$TS.json" && head -c 160 "$OUT/api-notes-$TS.json" && echo || echo "(sin body)"

echo "Hecho. Archivos en $OUT"
