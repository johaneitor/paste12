#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
# Crear nota y leer HTML una sola vez
ID=$(curl -fsS -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "text=single check $(date -u +%H:%M:%SZ) — 1234567890 abcdefghij" \
  "$BASE/api/notes" | sed -n 's/.*"id":[ ]*\([0-9]\+\).*/\1/p')
echo "ID=$ID"
HTML="$(curl -fsS "$BASE/?id=$ID&nosw=1&_=$(date +%s)")"
echo "$HTML" | tr -d '\n' | grep -Fqi '<meta name="p12-single"' && echo "OK meta"  || echo "sin meta"
echo "$HTML" | tr -d '\n' | grep -Fqi 'data-single="1"'        && echo "OK body"  || echo "sin body"
