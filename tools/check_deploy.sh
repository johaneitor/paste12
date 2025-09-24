#!/usr/bin/env bash
set -e
BASE="${1:?Uso: $0 https://host}"
LOCAL=$(git rev-parse HEAD | head -c 40)
REMOTE=$(curl -fsS "$BASE/api/deploy-stamp" | sed -n 's/.*"commit": *"\([0-9a-f]\{7,40\}\)".*/\1/p')
echo "Local:  $LOCAL"
echo "Remote: ${REMOTE:-<sin valor>}"
if [ -n "$REMOTE" ] && [ "$LOCAL" != "$REMOTE" ]; then
  echo "=> MISMATCH (producción no está en tu HEAD)"
  exit 1
else
  echo "=> OK (producción en tu HEAD)"
fi
