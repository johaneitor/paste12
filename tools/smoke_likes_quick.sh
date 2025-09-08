#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"

echo "== create JSON =="
nid="$(jq -n --arg t "smoke $(date -u +%H:%M:%SZ) texto largo para validar 1234567890 abcdefghij" '{text:$t}' \
      | curl -fsS -H 'Content-Type: application/json' --data-binary @- "$BASE/api/notes" | jq -r '.item.id')"
echo "note: ${nid:-<fail>}"

echo "== like/dedup =="
a="$(curl -fsS -X POST "$BASE/api/notes/$nid/like" | jq -r '.likes,.deduped' | paste -sd' ')"
b="$(curl -fsS -X POST "$BASE/api/notes/$nid/like" | jq -r '.likes,.deduped' | paste -sd' ')"
echo "$a -> $b"

echo "== race (5 likes FP=Z) =="
before="$(curl -fsS "$BASE/api/notes/$nid" | jq -r '.item.likes')"
seq 1 5 | xargs -I{} -P5 -n1 curl -fsS -o /dev/null -X POST "$BASE/api/notes/$nid/like" -H 'X-FP: Z'
after="$(curl -fsS "$BASE/api/notes/$nid" | jq -r '.item.likes')"
echo "delta=$((after-before))"
