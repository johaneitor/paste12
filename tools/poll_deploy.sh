#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"
TARGET="$(git rev-parse HEAD | head -c 40)"
for i in $(seq 1 48); do
  D="$(curl -fsS "$BASE/api/deploy-stamp" | sed -n 's/.*"commit": *"\([0-9a-f]\{7,40\}\)".*/\1/p' || true)"
  [ -n "$D" ] && echo "• intento $i: $D"
  [ "$D" = "$TARGET" ] && { echo "✓ Deploy == HEAD"; exit 0; }
  sleep 5
done
echo "✗ Timeout"; exit 2
