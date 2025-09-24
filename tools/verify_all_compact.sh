#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"
echo "== DEPLOY VS HEAD =="
LOCAL="$(git rev-parse HEAD | head -c 40)"
DEPLOY="$(curl -fsS "$BASE/api/deploy-stamp" | sed -n 's/.*"commit": *"\([0-9a-f]\{7,40\}\)".*/\1/p')"
echo "Local:  $LOCAL"; echo "Deploy: ${DEPLOY:-<sin valor>}"
[[ -n "$DEPLOY" && "$LOCAL" == "$DEPLOY" ]] && echo "✓ MATCH" || echo "✗ MISMATCH"
echo "---------------------------------------------"
echo "== HEADERS / =="; curl -sI "$BASE/" | awk 'BEGIN{IGNORECASE=1}/^(HTTP\/|cache-control:|x-(index-source|wsgi-bridge):)/{print}'
echo "---------------------------------------------"
echo "== UI marca/tagline =="; HTML="$(curl -fsS "$BASE/")"
echo "$HTML" | grep -qi '<title> *Paste12 *</title>' && echo "✓ title" || echo "✗ title"
echo "$HTML" | grep -qi '<h1[^>]*class="[^"]*\bbrand\b[^"]*"[^>]*> *Paste12 *<' && echo "✓ h1.brand" || echo "✗ h1.brand"
echo "$HTML" | grep -qi 'id="tagline".*(Reta|secreto|Confiesa)' && echo "✓ tagline" || echo "✗ tagline"
echo "---------------------------------------------"
echo "== LIKES (dedupe rápido) =="
NEW="$(curl -fsS -X POST "$BASE/api/notes" -H 'Content-Type: application/json' -d '{"text":"verify likes oc"}' | jq -r '.item.id')"
A="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes,.deduped' | paste -sd' ')"
B="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes,.deduped' | paste -sd' ')"
echo "same-FP: $A -> $B"
curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: a' >/dev/null
curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: b' >/dev/null
curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: c' >/dev/null
FINAL="$(curl -fsS "$BASE/api/notes/$NEW" | jq -r '.item.likes')"
echo "likes finales: $FINAL (esperado 4)"
