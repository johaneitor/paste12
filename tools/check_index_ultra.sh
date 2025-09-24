#!/usr/bin/env bash
set -e
BASE="${1:?Uso: $0 https://host}"

echo "== HEADERS / =="
curl -sI "$BASE/" | awk 'BEGIN{IGNORECASE=1}/^(HTTP\/|x-wsgi-bridge:|x-index-source:|cache-control:|cf-cache-status:|server:)/{print}'

echo "== PASTEL TOKEN =="
if curl -s "$BASE/" | grep -qm1 -- '--teal:#8fd3d0'; then
  echo "OK pastel"
else
  echo "NO pastel"
  exit 1
fi

echo "== NO-STORE =="
if curl -sI "$BASE/" | awk 'BEGIN{IGNORECASE=1}/^cache-control:/{print}' | grep -qi 'no-store'; then
  echo "OK no-store"
else
  echo "NO no-store"
  exit 1
fi
