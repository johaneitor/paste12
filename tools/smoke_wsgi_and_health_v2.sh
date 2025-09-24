#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p "$OUT"

echo "== Smoke WSGI =="

curl -fsS "$BASE/api/health" -o "$OUT/health-$TS.json" || true
if [[ -s "$OUT/health-$TS.json" ]]; then
  echo "health -> $OUT/health-$TS.json"
  sed -n '1p' "$OUT/health-$TS.json"
else
  echo "WARN: health vacío o error"
fi

curl -fsS -X OPTIONS -D "$OUT/options-$TS.txt" "$BASE/api/notes" -o /dev/null || true
[[ -s "$OUT/options-$TS.txt" ]] && echo "options -> $OUT/options-$TS.txt"

curl -fsS -D "$OUT/api-notes-h-$TS.txt" "$BASE/api/notes?limit=10" -o "$OUT/api-notes-$TS.json" || true
[[ -s "$OUT/api-notes-h-$TS.txt" ]] && echo "GET /api/notes headers -> $OUT/api-notes-h-$TS.txt"
[[ -s "$OUT/api-notes-$TS.json" ]] && echo "GET /api/notes body    -> $OUT/api-notes-$TS.json"

echo "Archivos en $OUT"
