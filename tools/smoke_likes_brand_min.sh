#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"

echo "== DEPLOY =="
curl -fsS "$BASE/api/deploy-stamp" | jq .

echo "== HEADERS / =="
curl -sI "$BASE/" | awk 'BEGIN{IGNORECASE=1}/^(HTTP\/|cache-control:|x-(index-source|wsgi-bridge):)/{print}'

echo "== HTML marca/tagline =="
HTML="$(curl -fsS "$BASE/")"
echo "$HTML" | grep -qi '<title> *Paste12 *</title>' && echo "✓ title Paste12" || echo "✗ title Paste12 ausente"
echo "$HTML" | grep -qi '<h1[^>]*class="[^"]*\bbrand\b[^"]*"[^>]*> *Paste12 *<' && echo "✓ h1.brand" || echo "✗ h1.brand ausente"
echo "$HTML" | grep -qi 'id="tagline".*(Reta|secreto|Confiesa)' && echo "✓ tagline" || echo "✗ tagline ausente"

echo "== LIKES DEDUPE =="
NEW=$(curl -fsS -X POST "$BASE/api/notes" -H 'Content-Type: application/json' -d '{"text":"smoke likes min"}' | jq -r '.item.id')
echo "id: $NEW"

L1=$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes, .deduped' | paste -sd' ')
echo "first: $L1"
L2=$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes, .deduped' | paste -sd' ')
echo "second: $L2"

A=$(echo "$L1" | awk '{print $1}')
B=$(echo "$L2" | awk '{print $1}')
if [ "$A" = "$B" ]; then echo "✓ dedupe misma FP ($A)"; else echo "✗ dedupe falló ($A -> $B)"; fi

for fp in a b c; do
  curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H "X-FP: $fp" | jq -c '{likes,deduped}' ; done
echo "final: $(curl -fsS "$BASE/api/notes/$NEW" | jq -r '.item.likes')"
