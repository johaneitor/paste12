#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"

# 1) Crear nota larga
BODY='{"text":"ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789","hours":12}'
NEW="$(curl -fsS -X POST "$BASE/api/notes" -H 'Content-Type: application/json' -d "$BODY" | jq -r '.item.id')"
echo "note: $NEW"

# 2) GET /api/notes?id -> debe traer summary de 20 chars + …
JSN="$(curl -fsS "$BASE/api/notes?limit=1")"
SUM="$(echo "$JSN" | jq -r '.items[0].summary')"
TXT="$(echo "$JSN" | jq -r '.items[0].text')"

echo "summary: $SUM"
echo "text   : $TXT"

# 3) single item también
ONE="$(curl -fsS "$BASE/api/notes/$NEW")"
SUM1="$(echo "$ONE" | jq -r '.item.summary')"
echo "summary (one): $SUM1"

# 4) headers diagnósticos
curl -sI "$BASE/api/notes?limit=1" | grep -i -E '^x-summary-(applied|limit):' || true
