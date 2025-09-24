#!/usr/bin/env bash
set -e
BASE="${1:?Uso: $0 https://host}"
echo "✓ HTTP 200 en /" && curl -sI "$BASE/" | head -n1
echo "✓ X-WSGI-Bridge presente" && curl -sI "$BASE/" | grep -qi '^x-wsgi-bridge:' && echo ok
if curl -sI "$BASE/" | awk 'tolower($0) ~ /^cache-control:/ {print}' | grep -qi 'no-store'; then
  echo "✓ Cache-Control no-store"
else
  echo "✗ falta Cache-Control no-store"; exit 1
fi
if curl -s "$BASE/" | grep -qm1 -- '--teal:#8fd3d0'; then
  echo "✓ Index pastel detectado"
else
  echo "✗ no se detecta index pastel"; exit 1
fi
