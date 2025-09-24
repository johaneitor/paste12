#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Usa: tools/smoke_core_backend_v1.sh https://tu-base}"
OUT="${2:-/sdcard/Download}"
ts="$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p "$OUT"

echo "health -> $OUT/health-$ts.json"
curl -fsS "$BASE/api/health" -o "$OUT/health-$ts.json" || true

echo "options -> $OUT/options-$ts.txt"
curl -i -fsS -X OPTIONS "$BASE/api/notes" -o "$OUT/options-$ts.txt" || true

echo "get headers -> $OUT/get-notes-h-$ts.txt"
curl -i -fsS "$BASE/api/notes?limit=5" -o "$OUT/get-notes-h-$ts.txt" || true

echo "get body -> $OUT/get-notes-$ts.json"
curl -fsS "$BASE/api/notes?limit=5" -o "$OUT/get-notes-$ts.json" || true

echo "post json -> $OUT/post-json-h-$ts.txt"
curl -i -fsS -H 'Content-Type: application/json' -d '{"text":"hello from smoke"}' "$BASE/api/notes" -o "$OUT/post-json-h-$ts.txt" || true

echo "post form -> $OUT/post-form-h-$ts.txt"
curl -i -fsS -F "text=hello form" "$BASE/api/notes" -o "$OUT/post-form-h-$ts.txt" || true

echo "neg like/view/report -> $OUT/negatives-h-$ts.txt"
{
  curl -i -fsS -X POST "$BASE/api/notes/999999/like"
  echo
  curl -i -fsS -X POST "$BASE/api/notes/999999/view"
  echo
  curl -i -fsS -X POST "$BASE/api/notes/999999/report"
  echo
} > "$OUT/negatives-h-$ts.txt" || true

echo "DONE. Archivos en $OUT (sufijo $ts)."
