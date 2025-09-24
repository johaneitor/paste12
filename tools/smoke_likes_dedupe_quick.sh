#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"
NEW="$(curl -fsS -X POST "$BASE/api/notes" -H 'Content-Type: application/json' -d '{"text":"smoke likes quick"}' | jq -r '.item.id')"
echo "id:" "$NEW"
R1="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like")"
R2="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like")"
echo "1st:" "$R1"
echo "2nd:" "$R2"
A="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: A' | jq -r '.likes')"
B="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: B' | jq -r '.likes')"
C="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: C' | jq -r '.likes')"
echo "likes FPs nuevas:" "$A" "->" "$B" "->" "$C"
