#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"
echo "== DEPLOY VS HEAD ==" 
LOCAL="$(git rev-parse HEAD | head -c 40)"
DEPLOY="$(curl -fsS "$BASE/api/deploy-stamp" | sed -n 's/.*"commit": *"\([0-9a-f]\{7,40\}\)".*/\1/p' || true)"
echo "Local:  $LOCAL"; echo "Deploy: ${DEPLOY:-<sin valor>}"
[ -n "$DEPLOY" ] && [ "$LOCAL" = "$DEPLOY" ] && echo "✓ MATCH" || echo "✗ MISMATCH"
echo "---------------------------------------------"
HTML="$(curl -fsS "$BASE/")"
echo "$HTML" | grep -qi '<title> *Paste12 *</title>' && echo "✓ title" || echo "✗ title"
echo "$HTML" | grep -qi '<h1[^>]*brand[^>]*> *Paste12 *<' && echo "✓ h1.brand" || echo "✗ h1.brand"
echo "$HTML" | grep -qi 'id="tagline".*(Reta|secreto|Confiesa)' && echo "✓ tagline" || echo "✗ tagline"
echo "---------------------------------------------"
NEW="$(curl -fsS -X POST "$BASE/api/notes" -H 'Content-Type: application/json' -d '{"text":"likes v3.1"}' | jq -r '.item.id')"
printf "same-FP: "; curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes,.deduped' | paste -sd' '; printf " -> "
curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes,.deduped' | paste -sd' '; echo
curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: a' >/dev/null
curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: b' >/dev/null
curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: c' >/dev/null
FINAL="$(curl -fsS "$BASE/api/notes/$NEW" | jq -r '.item.likes')"
echo "likes finales: $FINAL (esperado 4)"
