#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"

echo "== DEPLOY VS HEAD =="
LOCAL="$(git rev-parse HEAD | head -c 40)"
REMOTE="$(curl -fsS "$BASE/api/deploy-stamp" | sed -n 's/.*"commit": *"\([0-9a-f]\{7,40\}\)".*/\1/p')"
echo "Local:  $LOCAL"
echo "Remote: ${REMOTE:-<sin valor>}"
[ -n "$REMOTE" ] && [ "$LOCAL" = "$REMOTE" ] && echo "✓ MATCH" || echo "✗ MISMATCH"

echo "---------------------------------------------"
echo "== HEADERS / =="
curl -sI "$BASE/" | awk 'BEGIN{IGNORECASE=1}/^(HTTP\/|cache-control:|x-(index-source|wsgi-bridge):)/{print}'

HTML="$(curl -fsS "$BASE/")"
echo "---------------------------------------------"
echo "== HTML marca/tagline =="
echo "$HTML" | grep -qi '<title> *Paste12 *</title>' && echo "✓ title" || echo "✗ title"
echo "$HTML" | grep -qi '<h1[^>]*class="[^"]*\bbrand\b[^"]*"[^>]*> *Paste12 *<' && echo "✓ h1.brand" || echo "✗ h1.brand"
echo "$HTML" | grep -qi 'id="tagline".*(Reta|secreto|Confiesa)' && echo "✓ tagline" || echo "✗ tagline"

echo "---------------------------------------------"
echo "== SMOKE likes (dedupe) =="
NEW="$(curl -fsS -X POST "$BASE/api/notes" -H 'Content-Type: application/json' -d '{"text":"smoke likes"}' | jq -r '.item.id')"
echo "note id: $NEW"
a="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes,.deduped' | paste -sd' ')"
b="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes,.deduped' | paste -sd' ')"
echo "same-FP: $a -> $b"
A="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: A' | jq -r '.likes')"
B="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: B' | jq -r '.likes')"
C="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: C' | jq -r '.likes')"
echo "A/B/C: $A -> $B -> $C"
