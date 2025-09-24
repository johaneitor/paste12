#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; OUT="${2:-/sdcard/Download}"
[[ -n "$BASE" ]] || { echo "Uso: $0 BASE [OUTDIR]"; exit 2; }
mkdir -p "$OUT"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
H="$OUT/health-$TS.json"
O="$OUT/options-$TS.txt"
NH="$OUT/api-notes-headers-$TS.txt"
NB="$OUT/api-notes-$TS.json"

echo "-- health --"
curl -fsS "$BASE/api/health" -o "$H" && cat "$H" || true

echo -e "\n-- OPTIONS /api/notes --"
curl -isS -X OPTIONS "$BASE/api/notes" | tee "$O" >/dev/null

echo -e "\n-- GET /api/notes (headers) --"
curl -isS "$BASE/api/notes?limit=5" -H 'Accept: application/json' | sed -n '1,20p' | tee "$NH" >/dev/null

echo -e "\n-- POST JSON /api/notes --"
JSON_STATUS="$(curl -s -o /dev/null -w '%{http_code}' \
  -H 'Content-Type: application/json' -H 'Accept: application/json' \
  -d '{"text":"audit post json 1234567890","ttl_hours":1}' \
  "$BASE/api/notes")"
echo "status: $JSON_STATUS"

if [[ "$JSON_STATUS" != "201" && "$JSON_STATUS" != "200" ]]; then
  echo -e "\n-- POST FORM fallback /api/notes --"
  FORM_STATUS="$(curl -s -o /dev/null -w '%{http_code}' \
    -H 'Content-Type: application/x-www-form-urlencoded' -H 'Accept: application/json' \
    --data-urlencode 'text=audit post form 1234567890' --data-urlencode 'ttl_hours=1' \
    "$BASE/api/notes")"
  echo "status: $FORM_STATUS"
  if [[ "$FORM_STATUS" == "405" || "$JSON_STATUS" == "405" ]]; then
    echo "HINT: 405 = instancia equivocada o endpoint sin POST habilitado."
    echo "      ¿Estás en paste12-rmsk.onrender.com y no en pastel2… ?"
  fi
fi

echo -e "\nArchivos:"
printf "  %s\n" "$H" "$O" "$NH"
