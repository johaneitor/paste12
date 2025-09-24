#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p "$OUT"

echo "== health ==" | tee "$OUT/smoke-$TS.txt"
curl -sS "$BASE/api/health" | tee "$OUT/health-$TS.json" | sed -e $'s/^/  /' >> "$OUT/smoke-$TS.txt" || true

echo "== options ==" >> "$OUT/smoke-$TS.txt"
curl -i -sS -X OPTIONS "$BASE/api/notes" | tee "$OUT/options-$TS.txt" >/dev/null

echo "== post JSON ==" >> "$OUT/smoke-$TS.txt"
curl -i -sS "$BASE/api/notes" \
  -H "Content-Type: application/json" -d '{"text":"audit-json","hours":12}' \
  | tee "$OUT/post-json-h-$TS.txt" >/dev/null

echo "== post FORM ==" >> "$OUT/smoke-$TS.txt"
curl -i -sS -X POST "$BASE/api/notes/" \
  -F "text=audit-form" -F "hours=12" \
  | tee "$OUT/post-form-h-$TS.txt" >/dev/null

echo "== get notes ==" >> "$OUT/smoke-$TS.txt"
curl -i -sS "$BASE/api/notes?limit=5" | tee "$OUT/get-notes-h-$TS.txt" >/dev/null
curl -sS "$BASE/?debug=1&nosw=1&v=$RANDOM" -D "$OUT/index-headers-$TS.txt" -o "$OUT/index-$TS.html" >/dev/null
echo "Archivos en $OUT"
