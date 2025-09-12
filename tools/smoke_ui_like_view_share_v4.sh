#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }

echo "== health =="; curl -sS "$BASE/api/health" && echo

echo "== create (FORM fallback) =="
J='texto UI v4 smoke —— 1234567890 abcdefghij';
ID=$(curl -fsS -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "text=$J" "$BASE/api/notes" \
  | sed -n 's/.*"id":[ ]*\([0-9]\+\).*/\1/p')
echo "id=$ID"

echo "== like ==";  curl -sS -X POST "$BASE/api/notes/$ID/like" && echo
echo "== view ==";  curl -sS -X POST "$BASE/api/notes/$ID/view" && echo

echo "== single-page checks =="
HTML="$(curl -fsS "$BASE/?id=$ID&_=$(date +%s)")"

echo "$HTML" | grep -q 'name="p12-single"' \
  && echo "✓ meta p12-single" || echo "✗ sin meta p12-single"

echo "$HTML" | grep -q '<html[^>]*data-single-note="1"' \
  && echo "✓ html[data-single-note]" || echo "✗ sin data-single-note"

# también aceptar que haya exactamente 1 card
CNT=$(echo "$HTML" | tr -d '\n' | grep -o '<article[^>]*class="[^"]*note' | wc -l | tr -d ' ')
[ "$CNT" = "1" ] && echo "✓ 1 sola nota en la página" || echo "✗ se renderizaron $CNT notas"

echo "== share url =="
echo "$BASE/?id=$ID"
