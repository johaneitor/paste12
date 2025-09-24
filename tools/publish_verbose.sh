#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }

echo "---- JSON ----"
curl -sS -i -H 'Content-Type: application/json' \
  --data '{"text":"json prueba —— 1234567890 abcdefghij texto largo"}' \
  "$BASE/api/notes" | sed -n '1,40p'
echo

echo "---- FORM ----"
curl -sS -i -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "text=form prueba —— 1234567890 abcdefghij texto largo" \
  "$BASE/api/notes" | sed -n '1,40p'
echo
