#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p "$OUT"

echo "== Smoke =="
curl -fsS "$BASE/api/health" -o "$OUT/health-$TS.json" && echo "health -> $OUT/health-$TS.json"

curl -fsS -D "$OUT/options-$TS.txt" -o /dev/null -X OPTIONS "$BASE/api/notes" \
  && echo "options -> $OUT/options-$TS.txt" || true

curl -sS -D "$OUT/api-notes-h-$TS.txt" -o "$OUT/api-notes-b-$TS.json" "$BASE/api/notes" \
  && echo "GET /api/notes -> headers/body guardados" || true

echo "== FIN =="
