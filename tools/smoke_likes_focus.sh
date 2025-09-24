#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"
NEW="$(curl -fsS -X POST "$BASE/api/notes" -H 'Content-Type: application/json' -d '{"text":"focus like"}' | jq -r '.item.id')"
echo "id:" "$NEW"
one="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes,.deduped' | paste -sd' ')"
two="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes,.deduped' | paste -sd' ')"
echo "same-FP ->" "$one" "=>" "$two"
A="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: A' | jq -r '.likes')" 
B="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: B' | jq -r '.likes')"
echo "A/B ->" "$A" "->" "$B"
