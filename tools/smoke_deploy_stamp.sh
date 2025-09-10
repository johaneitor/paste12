#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }

echo "== GET /api/deploy-stamp (headers + body) =="
curl -sS -i "$BASE/api/deploy-stamp" | sed -n '1,80p'

echo "== Parseo (jq) =="
BODY="$(curl -fsS "$BASE/api/deploy-stamp" || true)"
if [ -z "$BODY" ]; then
  echo "✗ sin body (posible 500)"; exit 1
fi

# Aceptamos ambas formas: {deploy:{commit,date}} o {commit,date} (compat)
DEPLOY_COMMIT="$(jq -r '.deploy.commit // .commit // empty' <<<"$BODY" 2>/dev/null || true)"
DEPLOY_DATE="$(jq -r '.deploy.date // .date // empty'   <<<"$BODY" 2>/dev/null || true)"

echo "commit: ${DEPLOY_COMMIT:-<vacío>}"
echo "date:   ${DEPLOY_DATE:-<vacío>}"

[ -n "${DEPLOY_COMMIT:-}" ] || echo "⚠ commit vacío"
[ -n "${DEPLOY_DATE:-}" ]   || echo "⚠ date vacío"

# exit status “éxito” aunque falte alguno, para no cortar pipelines; ajusta si querés
exit 0
