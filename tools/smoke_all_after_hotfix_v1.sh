#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE}"
OUT="${2:-/sdcard/Download}"
mkdir -p "$OUT"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
echo "== Smoke FE/BE =="
curl -sS "$BASE/api/health" | tee "$OUT/health-$TS.json" >/dev/null

echo "-- OPTIONS /api/notes --"
curl -sS -i -X OPTIONS "$BASE/api/notes" | tee "$OUT/options-$TS.txt" >/dev/null

echo "-- POST JSON --"
curl -sS -i -H 'Content-Type: application/json' \
     -d '{"text":"hotfix smoke","hours":1}' \
     "$BASE/api/notes" | tee "$OUT/post-json-$TS.txt" >/dev/null

echo "-- GET index (cache bust) --"
curl -sS "$BASE/?nosw=1&v=$TS" > "$OUT/index-$TS.html" || true
grep -Eo 'googleads|adsbygoogle' "$OUT/index-$TS.html" >/dev/null && echo "AdSense: OK" || echo "AdSense: WARN"

echo "== Archivos en $OUT =="
ls -1 "$OUT"/*"$TS"* || true
