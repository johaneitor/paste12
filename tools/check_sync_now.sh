#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"
LOCAL="$(git rev-parse HEAD | head -c 40)"
REMOTE="$(curl -fsS "$BASE/api/deploy-stamp" | sed -n 's/.*"commit": *"\([0-9a-f]\{7,40\}\)".*/\1/p')"
echo "Local : $LOCAL"
echo "Deploy: ${REMOTE:-<sin valor>}"
test -n "$REMOTE" && [ "$LOCAL" = "$REMOTE" ] && echo "✓ MATCH (local == producción)" || echo "✗ MISMATCH"
