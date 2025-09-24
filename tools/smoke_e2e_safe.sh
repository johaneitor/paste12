#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
echo "== health =="; curl -sS "$BASE/api/health" && echo
echo "== preflight =="; curl -sS -i -X OPTIONS "$BASE/api/notes" | sed -n '1,15p'
echo "== index check (nosw) =="; curl -sS "$BASE/?nosw=1&_=$(date +%s)" | grep -qi 'name="p12-safe-shim"' && echo "OK safe-shim" || echo "X no shim"
echo "== create FORM =="; ID=$(curl -fsS -H 'Content-Type: application/x-www-form-urlencoded' --data-urlencode "text=smoke safe —— 1234567890 abcdefghij texto largo" "$BASE/api/notes" | sed -n 's/.*"id":[ ]*\([0-9]\+\).*/\1/p'); echo "id=$ID"
echo "== like =="; curl -sS -X POST "$BASE/api/notes/$ID/like" && echo
echo "== view =="; curl -sS -X POST "$BASE/api/notes/$ID/view" && echo
echo "== single page =="; curl -sS "$BASE/?id=$ID&nosw=1&_=$(date +%s)" | grep -qi '#'"$ID" && echo "OK single visible" || echo "X single no visible"
