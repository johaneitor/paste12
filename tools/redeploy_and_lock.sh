#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"

echo "== Disparando deploy (si no lo hiciste) =="
# opcional: tools/deploy_bump.sh || true

HEAD=$(git rev-parse HEAD | head -c 40)
echo "HEAD local: $HEAD"
echo "== Poll hasta que producción == HEAD =="
tries=0
while :; do
  REMOTE=$(curl -fsS "$BASE/api/deploy-stamp" | sed -n 's/.*"commit": *"\([0-9a-f]\{7,40\}\)".*/\1/p' || true)
  echo "deploy-stamp: ${REMOTE:-<sin valor>}"
  if [ -n "$REMOTE" ] && [ "$REMOTE" = "$HEAD" ]; then
    echo "✓ producción en HEAD"
    break
  fi
  tries=$((tries+1))
  if [ $tries -ge 60 ]; then
    echo "✗ no llegó a HEAD tras $tries intentos (revisa logs de build en Render)"
    exit 1
  fi
  sleep 5
done

echo "== Sanity de raíz / =="
curl -sI "$BASE/" | awk 'BEGIN{IGNORECASE=1}/^(HTTP\/|cache-control:|x-wsgi-bridge:|x-index-source:|server:)/{print}'
curl -fsS "$BASE/" | grep -qm1 -- '--teal:#8fd3d0' && echo "✓ pastel token" || echo "✗ pastel token ausente"

echo "OK: locked en HEAD."
