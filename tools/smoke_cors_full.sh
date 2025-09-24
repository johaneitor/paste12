#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
ORIG='https://example.com'

echo "== Preflight =="
curl -sS -i -X OPTIONS "$BASE/api/notes" \
  -H "Origin: $ORIG" \
  -H 'Access-Control-Request-Method: POST' | sed -n '1,80p'; echo

echo "== POST /api/notes con Origin (debe venir ACAO) =="
ID="$(printf '{"text":"cors full %s abcdefghij"}' "$(date -u +%H:%M:%SZ)" \
  | curl -fsS -i -H "Origin: $ORIG" -H 'Content-Type: application/json' --data-binary @- "$BASE/api/notes" \
  | tee /dev/stderr | { command -v jq >/dev/null && sed -n 's/.*\r$//;/^{/,$p' | jq -r '.item.id // .id // empty' || sed -n 's/.*\r$//;/^{/,$p'; })"
echo "id=$ID"
echo
echo "== Verifica ACAO en like =="
curl -sS -i -H "Origin: $ORIG" -X POST "$BASE/api/notes/$ID/like" | sed -n '1,80p'
