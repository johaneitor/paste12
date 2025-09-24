#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"

# Crear nota larga
NEW="$(curl -fsS -X POST "$BASE/api/notes" -H 'Content-Type: application/json' -d '{"text":"ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789","hours":12}' | jq -r '.item.id')"
echo "note: $NEW"

# Verificar JSON y headers
curl -sI "$BASE/api/notes?limit=1" | awk 'BEGIN{IGNORECASE=1}/^(HTTP\/|content-length:|content-type:|x-summary-)/{print}'
js="$(curl -fsS "$BASE/api/notes?limit=1")"
echo "$js" | jq '.items[0] | {id,summary,has_more}'

# Consistencia Content-Length
resp="$(curl -si "$BASE/api/notes?limit=1")"
cl="$(printf "%s" "$resp" | awk 'BEGIN{IGNORECASE=1}/^content-length:/{print $2}' | tr -d "\r")"
body="$(printf "%s" "$resp" | sed -n '/^\r\?$/,$p' | tail -n +2)"
len="$(printf "%s" "$body" | wc -c | awk '{print $1}')"
echo "CL=$cl actual=$len"
test "$cl" = "$len" && echo "✓ CL consistente" || echo "✗ CL mismatch"
