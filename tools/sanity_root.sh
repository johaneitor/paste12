#!/usr/bin/env bash
set -e
BASE="${1:?Uso: $0 https://host}"
echo "== HEADERS / =="
curl -sI "$BASE/" | awk 'BEGIN{IGNORECASE=1}/^(HTTP\/|x-wsgi-bridge:|x-index-source:|x-index-debug:|cache-control:|cf-cache-status:|server:)/{print}'
echo "== PASTEL =="
if curl -s "$BASE/" | grep -qm1 -- '--teal:#8fd3d0'; then echo OK; else echo NO; exit 1; fi
