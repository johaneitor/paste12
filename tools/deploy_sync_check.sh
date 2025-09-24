#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
REMOTE_SHA="$(curl -fsS "$BASE/api/deploy-stamp" | sed -n 's/.*"commit"[ ]*:[ ]*"\([0-9a-f]\{7,40\}\)".*/\1/p' | head -n1 || true)"
LOCAL_SHA="$(git rev-parse HEAD)"
ORIGIN_SHA="$(git rev-parse origin/main 2>/dev/null || echo "")"

echo "remote: ${REMOTE_SHA:-<vacío>}"
echo " local: $LOCAL_SHA"
[ -n "$ORIGIN_SHA" ] && echo "origin: $ORIGIN_SHA"

if [ -z "${REMOTE_SHA:-}" ]; then
  echo "✗ deploy-stamp vacío (o sin JSON)."
  exit 1
fi

if [ "$REMOTE_SHA" = "$LOCAL_SHA" ] || [ -n "$ORIGIN_SHA" ] && [ "$REMOTE_SHA" = "$ORIGIN_SHA" ]; then
  echo "✓ deploy y repo están alineados"
  exit 0
else
  echo "✗ mismatch: el deploy corre $REMOTE_SHA y tu repo está en $LOCAL_SHA"
  exit 2
fi
