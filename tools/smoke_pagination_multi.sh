#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; PAGES="${2:-3}"; LIMIT="${3:-5}"
[ -n "$BASE" ] || { echo "uso: $0 https://host [pages=3] [limit=5]"; exit 2; }

TMP="${TMPDIR:-/tmp}/pg.$$.tmp"; mkdir -p "${TMP%/*}"
say(){ echo -e "$*"; }
sep(){ echo "---------------------------------------------"; }

say "== Sembrar notas ($(("$PAGES" * "$LIMIT" + 1)) aprox.) =="
TOTAL=$(( PAGES * LIMIT + 1 ))
for i in $(seq 1 "$TOTAL"); do
  printf '{"text":"pg smoke %s #%02d 1234567890"}' "$(date -u +%H:%M:%SZ)" "$i" |
  curl -fsS -H 'Content-Type: application/json' --data-binary @- "$BASE/api/notes" >/dev/null || true
done
echo "creadas ~${TOTAL}"
sep

fetch_page () {
  local url="$1"
  curl -sS -D "$TMP.h" "$url" -o "$TMP.b" >/dev/null || true
  local status; status="$(sed -n '1p' "$TMP.h")"
  echo "status: $status"
  local link; link="$(grep -i '^link:' "$TMP.h" | sed -n 's/^[Ll]ink:\s*<\([^>]*\)>;.*$/\1/p')"
  if command -v jq >/dev/null; then
    jq -r '.items[]?.id' < "$TMP.b" | sed 's/^/id: /'
  else
    grep -o '"id":[0-9]\+' "$TMP.b" | cut -d: -f2 | sed 's/^/id: /'
  fi
  echo "::next::$link"
}

say "== Page 1 =="
NEXT="$(fetch_page "$BASE/api/notes?limit=$LIMIT" | tee "$TMP.p1" | sed -n 's/^::next::\(.*\)$/\1/p')"
sep
if [ -n "$NEXT" ] && [ "$PAGES" -ge 2 ]; then
  say "== Page 2 =="
  NEXT2="$(fetch_page "$BASE$NEXT" | tee "$TMP.p2" | sed -n 's/^::next::\(.*\)$/\1/p')"
  sep
fi
if [ -n "${NEXT2:-}" ] && [ "$PAGES" -ge 3 ]; then
  say "== Page 3 =="
  fetch_page "$BASE$NEXT2" | tee "$TMP.p3" >/dev/null
  sep
fi

say "== Validación básica de unicidad (ids no repetidos entre páginas mostradas) =="
if command -v jq >/dev/null; then
  IDS="$(for f in "$TMP.p1" ${NEXT:+$TMP.p2} ${NEXT2:+$TMP.p3}; do sed -n 's/^id: //p' "$f"; done)"
else
  IDS="$(for f in "$TMP.p1" ${NEXT:+$TMP.p2} ${NEXT2:+$TMP.p3}; do sed -n 's/^id: //p' "$f"; done)"
fi
CNT="$(echo "$IDS" | wc -w | tr -d ' ')"
UNQ="$(echo "$IDS" | tr ' ' '\n' | sort -n | uniq | wc -l | tr -d ' ')"
echo "count=$CNT unique=$UNQ"
[ "$CNT" = "$UNQ" ] && echo "✓ sin duplicados entre páginas" || echo "⚠ repetidos detectados"

echo "Listo."
