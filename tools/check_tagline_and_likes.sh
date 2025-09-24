#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"

echo "== HEADERS / ==" 
curl -sI "$BASE/" | awk 'BEGIN{IGNORECASE=1}/^(HTTP\/|cache-control:|x-(index-source|wsgi-bridge):)/{print}'

HTML="$(curl -fsS "$BASE/")"
CNT="$(printf "%s" "$HTML" | grep -oi '<div id="tagline"' | wc -l | awk '{print $1}')"
echo "taglines en HTML: $CNT"
if [ "$CNT" = "1" ]; then echo "✓ tagline único"; else echo "✗ hay duplicados"; fi

NEW="$(curl -fsS -X POST "$BASE/api/notes" -H 'Content-Type: application/json' -d '{"text":"tagline-smoke"}' | jq -r '.item.id')"
printf "same-FP: "; curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes,.deduped' | paste -sd' '; printf " -> "
curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes,.deduped' | paste -sd' '; echo
for x in a b c; do curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H "X-FP: $x" >/dev/null; done
FINAL="$(curl -fsS "$BASE/api/notes/$NEW" | jq -r '.item.likes')"
echo "likes finales: $FINAL (esperado 4)"
