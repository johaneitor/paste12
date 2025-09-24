#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"
echo "== LIKE GUARD CHECK =="
N="$(curl -fsS -X POST "$BASE/api/notes" -H 'Content-Type: application/json' -d '{"text":"verify likes guard"}' | jq -r '.item.id')"
echo "note:" "$N"
one="$(curl -fsS -X POST "$BASE/api/notes/$N/like" | jq -r '.likes,.deduped' | paste -sd' ')"
two="$(curl -fsS -X POST "$BASE/api/notes/$N/like" | jq -r '.likes,.deduped' | paste -sd' ')"
echo "same FP ->" "$one" "=>" "$two"
A="$(curl -fsS -X POST "$BASE/api/notes/$N/like" -H 'X-FP: A' | jq -r '.likes,.deduped' | paste -sd' ')"
B="$(curl -fsS -X POST "$BASE/api/notes/$N/like" -H 'X-FP: B' | jq -r '.likes,.deduped' | paste -sd' ')"
echo "A/B ->" "$A" " / " "$B"
echo "- Concurrencia x10 misma FP ..."
b4="$(curl -fsS "$BASE/api/notes/$N" | jq -r '.item.likes // 0')"
seq 1 10 | xargs -I{} -P 10 curl -fsS -X POST "$BASE/api/notes/$N/like" -H 'X-FP: CONC' >/dev/null
b5="$(curl -fsS "$BASE/api/notes/$N" | jq -r '.item.likes // 0')"
echo "delta concurrencia:" $((b5-b4)) "(<=1 es OK)"
