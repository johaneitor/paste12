#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"

echo "== index bytes =="
curl -sS "$BASE/?nosw=1&_=$(date +%s)" | wc -c

echo "== notes head =="
curl -sS -i "$BASE/api/notes?limit=3" | sed -n '1,20p'

echo "== create FORM =="
ID=$(curl -fsS -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "text=postfix smoke —— 1234567890 abcdefghij texto largo" \
  "$BASE/api/notes" | sed -n 's/.*"id":[ ]*\([0-9]\+\).*/\1/p'); echo "id=$ID"

echo "== like/view =="
curl -sS -X POST "$BASE/api/notes/$ID/like"; echo
curl -sS -X POST "$BASE/api/notes/$ID/view"; echo

echo "== single =="
curl -sS "$BASE/?id=$ID&nosw=1&_=$(date +%s)" | grep -qi '<meta name="p12-single"' && echo OK || echo "sin meta single"
