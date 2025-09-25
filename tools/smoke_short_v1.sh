#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p "$OUT"

echo "== smoke ($TS) ==" | tee "$OUT/smoke-$TS.txt"
echo "-- health --"      | tee -a "$OUT/smoke-$TS.txt"
curl -fsS "$BASE/api/health" | tee "$OUT/health-$TS.json" | tee -a "$OUT/smoke-$TS.txt"

echo -e "\n-- OPTIONS /api/notes --" | tee -a "$OUT/smoke-$TS.txt"
curl -i -sS -X OPTIONS "$BASE/api/notes" | tee "$OUT/options-$TS.txt" | sed -n '1,15p' | tee -a "$OUT/smoke-$TS.txt" >/dev/null

echo -e "\n-- GET /api/notes --" | tee -a "$OUT/smoke-$TS.txt"
curl -i -sS "$BASE/api/notes?limit=10" | tee "$OUT/api-notes-h-$TS.txt" | sed -n '1,15p' | tee -a "$OUT/smoke-$TS.txt" >/dev/null || true

echo -e "\n-- index quick --" | tee -a "$OUT/smoke-$TS.txt"
curl -sS "$BASE/" > "$OUT/index-$TS.html" || true
grep -q 'class="views"' "$OUT/index-$TS.html" && echo "OK views" | tee -a "$OUT/smoke-$TS.txt" || echo "FAIL views" | tee -a "$OUT/smoke-$TS.txt"
grep -qi 'google-adsense-account' "$OUT/index-$TS.html" && echo "OK ads meta" | tee -a "$OUT/smoke-$TS.txt" || echo "WARN ads meta" | tee -a "$OUT/smoke-$TS.txt"

echo -e "\n== files ==" | tee -a "$OUT/smoke-$TS.txt"
ls -1 "$OUT" | sed "s/^/  /" | tee -a "$OUT/smoke-$TS.txt"
echo "Guardado: $OUT/smoke-$TS.txt"
