#!/usr/bin/env bash
set -euo pipefail

BASE="${1:?Uso: $0 https://host}"

echo "== HEADERS / =="
curl -sI "$BASE/" | awk 'BEGIN{IGNORECASE=1}/^(HTTP\/|x-wsgi-bridge:|x-index-source:|cache-control:|cf-cache-status:|server:)/{print}'

echo "== TOKEN pastel en / =="
if curl -fsS "$BASE/" | grep -qm1 -- '--teal:#8fd3d0'; then
  echo "OK pastel"
else
  echo "NO pastel"
  exit 1
fi

echo "== GET /api/notes?limit=2 =="
curl -isS "$BASE/api/notes?limit=2" | sed -n '1,20p' | awk 'BEGIN{IGNORECASE=1}/^(HTTP\/|link:|x-next-cursor:)/{print}'
echo "-- body --"
curl -fsS "$BASE/api/notes?limit=2" | jq '{count: (.items|length), next}'

# Seguir al "next", si existe
NEXT=$(curl -fsS "$BASE/api/notes?limit=2" | jq -r '.next | @uri "cursor_ts=\(.cursor_ts)&cursor_id=\(.cursor_id)"')
if [ -n "$NEXT" ] && [ "$NEXT" != "null" ]; then
  echo "== GET next page =="
  curl -fsS "$BASE/api/notes?limit=2&$NEXT" | jq '{count: (.items|length), next}'
fi

echo "== HEAD /api/notes (esperado sin cuerpo) =="
HHEAD=$(curl -sI "$BASE/api/notes?limit=1")
echo "$HHEAD" | awk 'BEGIN{IGNORECASE=1}/^(HTTP\/|content-length:|x-next-cursor:)/{print}'
if echo "$HHEAD" | awk 'BEGIN{IGNORECASE=1}/^content-length:/{print}' | grep -qiE '^content-length:\s*0\s*$'; then
  echo "OK sin cuerpo"
else
  echo "AVISO: Content-Length no es 0 (HEAD con cuerpo)"
fi

echo "== POST + like/view/report (dedupe + remove al 5º) =="
NEW=$(curl -fsS -X POST "$BASE/api/notes" -H 'content-type: application/json' -d '{"text":"smoke ✅"}' | jq -r '.item.id')
echo "ID: $NEW"

curl -fsS -X POST "$BASE/api/notes/$NEW/like" >/dev/null
curl -fsS -X POST "$BASE/api/notes/$NEW/view" >/dev/null

echo "-- report (misma persona, no debe sumar dos veces) --"
curl -fsS -X POST "$BASE/api/notes/$NEW/report" | jq .
curl -fsS -X POST "$BASE/api/notes/$NEW/report" | jq .

echo "-- report desde 4 fingerprints distintas --"
for fp in u2 u3 u4 u5; do
  curl -fsS -X POST "$BASE/api/notes/$NEW/report" -H "X-FP: $fp" | jq .
done

echo "== GET por id (si se removió, not_found) =="
curl -fsS "$BASE/api/notes/$NEW" | jq .
