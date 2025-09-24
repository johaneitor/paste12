#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"
echo "== HEADERS / ==" 
curl -sI "$BASE/?_=$(date +%s)" | awk 'BEGIN{IGNORECASE=1}/^(HTTP\/|x-wsgi-bridge:|x-index-source:|cache-control:|server:|cf-cache-status:)/{print}'
echo "== PASTEL =="
curl -s "$BASE/?_=$(date +%s)" | grep -qm1 -- '--teal:#8fd3d0' && echo "OK pastel" || echo "NO pastel"
echo "== NO-STORE =="
curl -sI "$BASE/?_=$(date +%s)" | awk 'BEGIN{IGNORECASE=1}/^cache-control:/{print}' | grep -qi 'no-store' && echo "OK no-store" || echo "NO no-store"
