#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; ID="${2:-}"
[ -n "$BASE" ] || { echo "uso: $0 https://host [ID]"; exit 2; }

if [ -z "${ID:-}" ]; then
  ID=$(curl -fsS "$BASE/api/notes?limit=1" | sed -n 's/.*"id":[ ]*\([0-9]\+\).*/\1/p' || true)
  [ -n "$ID" ] || { echo "✗ no pude obtener ID de /api/notes?limit=1"; exit 1; }
fi

H="$(curl -sS "$BASE/?id=$ID&nosw=1&_=$(date +%s)")"
if echo "$H" | grep -qi 'name="p12-single"'; then
  echo "✓ single (meta p12-single)"
elif echo "$H" | grep -qi 'data-single="1"'; then
  echo "✓ single (body data-single)"
else
  echo "✗ no se detecta single ni por meta ni por body"
fi
