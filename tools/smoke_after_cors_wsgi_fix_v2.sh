#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
ts="$(date -u +%Y%m%d-%H%M%SZ)"

mkdir -p "$OUT"

echo "== Smoke WSGI/CORS =="
echo -n "health -> "
curl -fsS "$BASE/api/health" -o "$OUT/health-$ts.json" && cat "$OUT/health-$ts.json" || true
echo

echo -n "options -> "
curl -fsS -I -X OPTIONS "$BASE/api/notes" -o "$OUT/options-$ts.txt" && echo "$OUT/options-$ts.txt" || true

echo -n "GET /api/notes headers -> "
curl -fsS -D "$OUT/api-notes-h-$ts.txt" -o "$OUT/api-notes-b-$ts.json" "$BASE/api/notes?limit=5" >/dev/null 2>&1 \
  && echo "$OUT/api-notes-h-$ts.txt" || echo "FAIL"

echo "Archivos en $OUT"
ls -1 "$OUT" | tail -n 10 | sed 's/^/  /'
