#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"

mkdir -p "$OUT"

echo "== Smoke health ==" | tee "$OUT/smoke-$TS.txt"
curl -fsS "$BASE/api/health" | tee "$OUT/health-$TS.json" && echo

echo "== Publish test ==" | tee -a "$OUT/smoke-$TS.txt"
TEXT="test suite $(date -u +%H:%M:%S)"
JSON_STATUS=; FORM_STATUS=
for ep in /api/notes /api/note /api/notes/create /api/create /api/publish; do
  JSON_STATUS=$(curl -s -o "$OUT/publish-json-$TS.json" -w "%{http_code}" -H 'Content-Type: application/json' -H 'Accept: application/json' -d "{\"text\":\"$TEXT\",\"ttl_hours\":12}" "$BASE$ep" || true)
  if [ "$JSON_STATUS" = "201" ] || [ "$JSON_STATUS" = "200" ]; then
    echo "OK JSON $ep $JSON_STATUS" | tee -a "$OUT/smoke-$TS.txt"
    break
  fi
  FORM_STATUS=$(curl -s -o "$OUT/publish-form-$TS.json" -w "%{http_code}" -H 'Content-Type: application/x-www-form-urlencoded' -H 'Accept: application/json' --data-urlencode "text=$TEXT" --data-urlencode "ttl_hours=12" "$BASE$ep" || true)
  if [ "$FORM_STATUS" = "201" ] || [ "$FORM_STATUS" = "200" ]; then
    echo "OK FORM $ep $FORM_STATUS" | tee -a "$OUT/smoke-$TS.txt"
    break
  fi
done

echo "== UI check (tagline único) ==" | tee -a "$OUT/smoke-$TS.txt"
curl -fsS "$BASE/?debug=1&nosw=1&v=$RANDOM" -o "$OUT/index-$TS.html"
H2=$(grep -ci 'id="tagline-rot"' "$OUT/index-$TS.html" || true)
P1=$(grep -ci 'id="tagline"' "$OUT/index-$TS.html" || true)
if [ "$H2" -ge 1 ] && [ "$P1" -eq 0 ]; then
  echo "OK - subtítulo único" | tee -a "$OUT/smoke-$TS.txt"
else
  echo "FAIL - subtítulo duplicado (H2:$H2 P:$P1)" | tee -a "$OUT/smoke-$TS.txt"
fi

echo "== GET /api/notes ==" | tee -a "$OUT/smoke-$TS.txt"
curl -fsS -D "$OUT/api-notes-h-$TS.txt" "$BASE/api/notes?limit=5" -o "$OUT/api-notes-$TS.json" || true
echo "Archivos:"
printf "  %s\n" "$OUT/health-$TS.json" "$OUT/index-$TS.html" "$OUT/smoke-$TS.txt" "$OUT/api-notes-h-$TS.txt" "$OUT/api-notes-$TS.json"
