#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; THRESHOLD="${2:-5}"; PGLIM="${3:-5}"
[ -n "$BASE" ] || { echo "uso: $0 https://host [report_threshold=5] [page_limit=5]"; exit 2; }

TMP="${TMPDIR:-/tmp}/smoke.$$.tmp"
mkdir -p "${TMP%/*}"

say(){ echo -e "$*"; }
sep(){ echo "---------------------------------------------"; }

say "== /api/health =="
curl -sS -i "$BASE/api/health" | sed -n '1,40p'
sep

say "== Crear nota base =="
NEW_ID="$(
  printf '{"text":"reports smoke %s abcdefghij"}' "$(date -u +%H:%M:%SZ)" |
  curl -fsS -H 'Content-Type: application/json' --data-binary @- "$BASE/api/notes" |
  { command -v jq >/dev/null && jq -r '.item.id // .id // empty' || sed -n 's/.*"id":\s*\([0-9]\+\).*/\1/p'; }
)"
[ -n "$NEW_ID" ] || { echo "✗ no obtuve id de creación"; exit 1; }
echo "id=${NEW_ID}"
sep

say "== TTL medido (expires_at - timestamp) =="
BODY="$(curl -fsS "$BASE/api/notes/$NEW_ID")"
if command -v jq >/dev/null; then
  TS="$(echo "$BODY" | jq -r '.item.timestamp // .timestamp')"
  EXP="$(echo "$BODY" | jq -r '.item.expires_at // .expires_at')"
  echo "timestamp:  $TS"
  echo "expires_at: $EXP"
else
  echo "$BODY" | head -n 1
fi
sep

say "== Reportes con huellas distintas (umbral ${THRESHOLD}) =="
for k in $(seq 1 "$THRESHOLD"); do
  UA="smoke-report/$k"
  IP="203.0.113.$k"
  CODE="$(curl -sS -o "$TMP.out" -w '%{http_code}' -X POST "$BASE/api/notes/$NEW_ID/report" \
    -H "User-Agent: $UA" -H "X-Forwarded-For: $IP")"
  MSG="$(cat "$TMP.out")"
  echo "[$k/$THRESHOLD] code=$CODE body=${MSG:0:160}"
done
sep

say "== GET por id tras umbral (esperado: 404 si se elimina/oculta) =="
curl -sS -i "$BASE/api/notes/$NEW_ID" | sed -n '1,40p'
sep

say "== Paginación (limit=${PGLIM}) — id no debería aparecer si fue removida =="
curl -sS -D "$TMP.h" "$BASE/api/notes?limit=$PGLIM" -o "$TMP.b" >/dev/null || true
head -n 1 "$TMP.h"
if command -v jq >/dev/null; then
  IDS="$(jq -r '.items[]?.id' < "$TMP.b" | xargs echo)"
else
  IDS="$(grep -o '"id":[0-9]\+' "$TMP.b" | cut -d: -f2 | xargs echo)"
fi
echo "ids página 1: $IDS"
echo "$IDS" | grep -qw "$NEW_ID" && echo "⚠ id $NEW_ID visible todavía" || echo "✓ id $NEW_ID no listado"
sep

echo "Listo."
