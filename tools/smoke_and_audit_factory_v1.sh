#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
ts="$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p "$OUT"

curl -fsS "$BASE/api/health" -o "$OUT/health-$ts.json" || true
echo "health -> $OUT/health-$ts.json"

curl -i -s -X OPTIONS "$BASE/api/notes" -o "$OUT/options-$ts.txt" || true
echo "options -> $OUT/options-$ts.txt"

curl -i -s "$BASE/api/notes?limit=10" -o "$OUT/api-notes-h-$ts.txt" || true
echo "GET /api/notes headers -> $OUT/api-notes-h-$ts.txt"
curl -s "$BASE/api/notes?limit=10" -o "$OUT/api-notes-$ts.json" || true
head -n 1 "$OUT/api-notes-$ts.json" || true

# POST JSON
curl -i -s -H 'Content-Type: application/json' \
  -d '{"text":"factory smoke json 123456"}' \
  "$BASE/api/notes" -o "$OUT/post-json-h-$ts.txt" || true
echo "POST JSON -> $OUT/post-json-h-$ts.txt"

# POST FORM
curl -i -s -F 'text=factory smoke form 123' \
  "$BASE/api/notes" -o "$OUT/post-form-h-$ts.txt" || true
echo "POST FORM -> $OUT/post-form-h-$ts.txt"

# Negativos (ID muy alto)
for ep in like view report; do
  curl -i -s -X POST "$BASE/api/notes/999999/$ep" -o "$OUT/neg-$ep-h-$ts.txt" || true
  echo "NEG $ep -> $OUT/neg-$ep-h-$ts.txt"
done

# HTML principal (para validar AdSense/head)
curl -s "$BASE/" -o "$OUT/index-$ts.html" || true
echo "index -> $OUT/index-$ts.html"

# Resumen
{
  echo "== Smoke Factory =="
  echo "base: $BASE"
  echo "ts  : $ts"
  echo
  echo "Archivos:"
  ls -1 "$OUT"/*"$ts"* 2>/dev/null || true
} > "$OUT/smoke-factory-$ts.txt"
echo "Resumen: $OUT/smoke-factory-$ts.txt"
