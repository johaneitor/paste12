#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL}"
: "${RENDER_DEPLOY_HOOK:?Definí RENDER_DEPLOY_HOOK con la URL del deploy hook}"
HEAD="$(git rev-parse HEAD)"
echo "HEAD local: $HEAD"
echo "Disparando deploy…"
curl -fsS -X POST "$RENDER_DEPLOY_HOOK" -H 'Accept: application/json' -d '{}' >/dev/null || {
  echo "ERROR: no se pudo disparar el deploy (RENDER_DEPLOY_HOOK)"; exit 2; }
echo "Esperando a que remoto == $HEAD …"
end=$((SECONDS+480))
while (( SECONDS<end )); do
  remote="$(curl -fsS "$BASE/api/deploy-stamp" | sed -n 's/.*"commit"[": ]*\([0-9a-f]\{7,40\}\).*/\1/p' || true)"
  [[ -z "$remote" ]] && remote="$(curl -fsS "$BASE" | sed -n 's/.*name="p12-commit" content="\([0-9a-f]\{7,40\}\)".*/\1/p' || true)"
  echo "remote: ${remote:-unknown}"
  [[ -n "$remote" && "$remote" = "$HEAD" ]] && { echo "✓ Deploy alineado"; exit 0; }
  sleep 6
done
echo "✗ Timeout esperando deploy"; exit 1
