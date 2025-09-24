#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"

say(){ printf "%s\n" "$*"; }
hr(){ printf "%s\n" "---------------------------------------------"; }

say "== DEPLOY VS HEAD =="
LOCAL="$(git rev-parse HEAD | head -c 40 2>/dev/null || true)"
REMOTE="$(curl -fsS "$BASE/api/deploy-stamp" | sed -n 's/.*"commit": *"\([0-9a-f]\{7,40\}\)".*/\1/p' || true)"
say "Local:  ${LOCAL:-<n/a>}"
say "Remote: ${REMOTE:-<n/a>}"
[ -n "$LOCAL" ] && [ "$LOCAL" = "$REMOTE" ] && say "✓ deploy en HEAD" || say "✗ deploy distinto de HEAD"
hr

say "== HEADERS / =="
curl -sI "$BASE/" | awk 'BEGIN{IGNORECASE=1}/^(HTTP\/|cache-control:|x-(index-source|wsgi-bridge):|server:|cf-cache-status:)/{print}'
hr

say "== HTML marca/tagline =="
HTML="$(curl -fsS "$BASE/")"
echo "$HTML" | grep -qi '<title> *Paste12 *</title>' && say "✓ title Paste12" || say "✗ title Paste12 ausente"
echo "$HTML" | grep -qi '<h1[^>]*class="[^"]*\bbrand\b[^"]*"[^>]*> *Paste12 *<' && say "✓ h1.brand Paste12" || say "✗ h1.brand ausente"
echo "$HTML" | grep -qi 'id="tagline".*(Reta|secreto|Confiesa)' && say "✓ tagline lúdico" || say "✗ tagline ausente"
hr

say "== SMOKE likes dedupe =="
NEW=$(curl -fsS -X POST "$BASE/api/notes" -H 'Content-Type: application/json' -d '{"text":"smoke likes dedupe"}' | jq -r '.item.id')
say "nota id: $NEW"

base=$(curl -fsS "$BASE/api/notes/$NEW" | jq -r '.item.likes // 0')
say "likes base: $base"

a1=$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes')
a2=$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes')
if [ "$a1" = "$a2" ]; then say "✓ dedupe misma FP ($a1)"; else say "✗ dedupe misma FP falló ($a1 -> $a2)"; fi

b1=$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: alpha' | jq -r '.likes')
b2=$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: beta'  | jq -r '.likes')
b3=$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: gamma' | jq -r '.likes')
say "likes tras FPs nuevas: $b1 -> $b2 -> $b3"

final=$(curl -fsS "$BASE/api/notes/$NEW" | jq -r '.item.likes // 0')
exp=$(( base + 1 + 3 )) # 1 de la primera FP + 3 FPs nuevas
if [ "$final" -eq "$exp" ]; then
  say "✓ total esperado: $final (base $base +4 únicas)"
else
  say "✗ total inesperado: $final (esperado $exp)"
fi
hr

say "== FIN =="
