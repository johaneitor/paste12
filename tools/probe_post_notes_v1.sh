#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p "$OUT"
echo "== probe POST /api/notes =="
echo "BASE=$BASE  TS=$TS"
TEXT="Prober $(date -u +%H:%M:%S) — nota de prueba automatizada"
JSON="$OUT/probe-post-json-$TS.json"
FORM="$OUT/probe-post-form-$TS.json"

set +e
curl -sS -f -m 20 -H 'Content-Type: application/json' -H 'Accept: application/json' \
     -d "{\"text\":\"$TEXT\",\"ttl_hours\":1}" "$BASE/api/notes" -o "$JSON"
CJ=$?; set -e
echo "json_exit=$CJ  file:$JSON"
if [[ $CJ -ne 0 ]]; then
  curl -sS -m 20 -H 'Content-Type: application/x-www-form-urlencoded' -H 'Accept: application/json' \
       --data-urlencode "text=$TEXT" --data-urlencode "ttl_hours=1" "$BASE/api/notes" -o "$FORM" || true
  echo "form_saved:$FORM"
fi
