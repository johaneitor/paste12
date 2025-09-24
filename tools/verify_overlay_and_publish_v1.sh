#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Usa: tools/verify_overlay_and_publish_v1.sh https://tu-app.onrender.com}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"

mkdir -p "$OUT"

echo "== health =="
curl -sS "$BASE/api/health" | tee "$OUT/health-$TS.json"

echo "== headers / (overlay) =="
curl -sSI "$BASE/?v=$TS" | tee "$OUT/index-headers-$TS.txt" >/dev/null

echo "== OPTIONS /api/notes =="
curl -sSI -X OPTIONS "$BASE/api/notes" | tee "$OUT/options-$TS.txt" >/dev/null

echo "== POST JSON /api/notes =="
curl -sS -D "$OUT/post-json-h-$TS.txt" -o "$OUT/post-json-b-$TS.txt" \
  -H 'Content-Type: application/json' \
  -X POST "$BASE/api/notes" \
  --data "{\"text\":\"audit $TS\",\"hours\":1}" || true

echo "== GET /api/notes =="
curl -sS -D "$OUT/get-notes-h-$TS.txt" -o "$OUT/get-notes-b-$TS.json" \
  "$BASE/api/notes?limit=5" || true

echo "== FIN =="
