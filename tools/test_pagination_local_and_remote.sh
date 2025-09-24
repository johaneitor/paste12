#!/usr/bin/env bash
set -Eeuo pipefail
BASE_LOCAL="http://127.0.0.1:8000"
BASE_REMOTE="${1:-https://paste12-rmsk.onrender.com}"

echo "== Local =="
H1="$(mktemp)"
curl -sSI "$BASE_LOCAL/api/notes?limit=2" | tr -d '\r' | tee "$H1" >/dev/null
NEXT_LOCAL="$(awk -F': ' 'tolower($1)=="x-next-after"{print $2}' "$H1" | tr -d '\r\n')"
echo "NEXT_LOCAL=${NEXT_LOCAL:-<vacío>}"
curl -sS "$BASE_LOCAL/api/notes?after_id=$NEXT_LOCAL&limit=2" | python -m json.tool || true
echo

echo "== Remote ($BASE_REMOTE) =="
H2="$(mktemp)"
curl -sSI "$BASE_REMOTE/api/notes?limit=2" | tr -d '\r' | tee "$H2" >/dev/null
NEXT_REMOTE="$(awk -F': ' 'tolower($1)=="x-next-after"{print $2}' "$H2" | tr -d '\r\n')"
echo "NEXT_REMOTE=${NEXT_REMOTE:-<vacío>}"
curl -sS "$BASE_REMOTE/api/notes?after_id=$NEXT_REMOTE&limit=2" | python -m json.tool || true
