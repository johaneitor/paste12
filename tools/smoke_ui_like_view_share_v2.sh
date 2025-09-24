#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }

say(){ echo -e "$*"; }
json(){ jq -r "$1" 2>/dev/null || sed -n 's/.*"'"$1"'":\s*"\?\([^",}]\+\).*/\1/p'; }

say "== health =="; curl -fsS "$BASE/api/health" && echo

say "== list (peek) =="; curl -fsS "$BASE/api/notes?limit=3" | sed -n '1,120p'

say "== create (FORM fallback) =="
TXT="ui smoke $(date -u +%H:%M:%SZ) — 1234567890 abcdefghij texto lo suficientemente largo"
CRE=$(curl -sS -D- -o /dev/stdout -X POST "$BASE/api/notes" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "text=$TXT")
echo "$CRE" | sed -n '1,40p'
ID=$(echo "$CRE" | sed -n 's/.*"id":[ ]*\([0-9]\+\).*/\1/p' | head -n1)
[ -n "$ID" ] || { echo "✗ no pude extraer id"; exit 1; }
echo "id=$ID"

say "== like =="; curl -fsS -X POST "$BASE/api/notes/$ID/like" | sed -n '1,120p'
say "== view =="; curl -fsS -X POST "$BASE/api/notes/$ID/view" | sed -n '1,120p'

say "== single note page check =="
HTML=$(curl -fsS "$BASE/?id=$ID&_=$(date +%s)")
echo "$HTML" | sed -n '1,60p' >/dev/null
if echo "$HTML" | grep -qi '<meta[^>]*name=["'"'"']p12-single["'"'"'][^>]*content=["'"'"']1'; then
  echo "✓ meta p12-single=1"
else
  echo "⚠ sin meta p12-single"
fi
if echo "$HTML" | grep -qi 'data-single-note="1"'; then
  echo "✓ html[data-single-note=1]"
else
  echo "⚠ sin data-single-note"
fi

say "== share url =="
echo "$BASE/?id=$ID"
echo "Listo."
