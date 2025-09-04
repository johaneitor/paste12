#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"
L="$(git rev-parse HEAD | head -c 40)"
D="$(curl -fsS "$BASE/api/deploy-stamp" | sed -n 's/.*"commit": *"\([0-9a-f]\{7,40\}\)".*/\1/p')"
if [ -z "$D" ] || [ "$L" != "$D" ]; then
  echo "✗ HEAD != deploy ($L != ${D:-<n/a>}). Sincronizá primero."
  exit 1
fi
echo "✓ HEAD == deploy ($L)"
