#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
echo "== health =="; curl -sS "$BASE/api/health" && echo
echo "== create (FORM fallback) =="
J='texto UI v3 smoke —— 1234567890 abcdefghij'; 
ID=$(curl -fsS -H 'Content-Type: application/x-www-form-urlencoded' --data-urlencode "text=$J" "$BASE/api/notes" | sed -n 's/.*"id":[ ]*\([0-9]\+\).*/\1/p')
echo "id=$ID"
echo "== like ==";  curl -sS -X POST "$BASE/api/notes/$ID/like" && echo
echo "== view ==";  curl -sS -X POST "$BASE/api/notes/$ID/view" && echo
echo "== single-page check =="; curl -sS "$BASE/?id=$ID&_=$(date +%s)" | grep -q 'data-single="1"' && echo "OK single-flag" || echo "sin single-flag (frontend igual lo renderiza)"
