#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"
TXT="${2:-aqui va un texto de prueba suficientemente largo para pasar mínimos de validación (>= 40-60 chars).}"

hdrs=(-H 'Accept: application/json')

echo "== Variante A: JSON --data-binary =="
jq -n --arg t "$TXT" '{text:$t}' \
| curl -sS -i "${hdrs[@]}" -H 'Content-Type: application/json' --data-binary @- "$BASE/api/notes"
echo

echo "== Variante B: form-urlencoded =="
curl -sS -i "${hdrs[@]}" -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "text=$TXT" "$BASE/api/notes"
echo
