#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
HTML="$(curl -fsS "$BASE/?_=$(date +%s)")"
if echo "$HTML" | grep -q 'P12 COHESION V7'; then
  echo "OK: index.html sirve el bloque v7"
else
  echo "✗ No veo el marcador v7 en index.html"
  exit 1
fi
