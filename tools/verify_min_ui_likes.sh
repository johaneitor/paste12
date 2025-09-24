#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?uso: $0 https://host}"
HTML="$(curl -fsS "$BASE/")"
echo "$HTML" | grep -qi '<title> *Paste12 *</title>' && echo "✓ title" || echo "✗ title"
echo "$HTML" | grep -qi '<h1[^>]*class="[^"]*\bbrand\b[^"]*"[^>]*> *Paste12 *<' && echo "✓ h1.brand" || echo "✗ h1.brand"
echo "$HTML" | grep -qi 'id="tagline".*(Reta|secreto|Confiesa)' && echo "✓ tagline" || echo "✗ tagline"

NEW="$(curl -fsS -X POST "$BASE/api/notes" -H 'Content-Type: application/json' -d '{"text":"like smoke ok"}' | jq -r '.item.id')"
echo "note: $NEW"
S1="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes,.deduped' | paste -sd' ')"
S2="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes,.deduped' | paste -sd' ')"
echo "same-FP: $S1 -> $S2"
curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: a' >/dev/null
curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: b' >/dev/null
curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: c' >/dev/null
FINAL="$(curl -fsS "$BASE/api/notes/$NEW" | jq -r '.item.likes')"
echo "likes finales: $FINAL (esperado 4)"
