#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"
echo "== /api/health =="; curl -sI "$BASE/api/health" | sed -n '1p'
echo "== create JSON ==";
NEW="$(jq -n --arg t "purify $(date -u +%H:%M:%SZ) texto largo de validación 1234567890 abcdefghij" '{text:$t}' \
 | curl -fsS -H 'Content-Type: application/json' --data-binary @- "$BASE/api/notes" | jq -r '.item.id')"
echo "note: ${NEW:-<fail>}"
[ -n "${NEW:-}" ] || exit 1
echo "== like/dedup =="
A="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes,.deduped' | paste -sd' ')"
B="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes,.deduped' | paste -sd' ')"
echo "$A -> $B"
