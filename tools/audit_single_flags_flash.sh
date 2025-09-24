#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
ID=$(curl -fsS "$BASE/api/notes?limit=1" | sed -n 's/.*"id":[ ]*\([0-9]\+\).*/\1/p')
HTML="$(curl -fsS "$BASE/?id=$ID&nosw=1&_=$(date +%s)")"
echo "ID=$ID"
echo "$HTML" | tr -d '\n' | grep -Fqi '<meta name="p12-single"' && echo "OK meta"  || echo "sin meta"
echo "$HTML" | tr -d '\n' | grep -Fqi 'data-single="1"'        && echo "OK body"  || echo "sin body"
