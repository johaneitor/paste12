#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
HTML="$(curl -fsS "$BASE/")"
if echo "$HTML" | grep -q 'id="p12-min-client"'; then
  echo "✓ mini-cliente presente en index.html"
else
  echo "✗ mini-cliente NO encontrado"; exit 1
fi
