#!/usr/bin/env bash
set -euo pipefail
ok=0
if [[ -z "${RENDER_API_KEY:-}" ]]; then echo "FALTA RENDER_API_KEY"; exit 1; fi
if [[ -z "${RENDER_SERVICE_ID:-}" ]]; then echo "FALTA RENDER_SERVICE_ID"; exit 1; fi
[[ "$RENDER_API_KEY" =~ ^rv_ ]] || { echo "API key con formato raro (debe empezar rv_)"; ok=1; }
[[ "$RENDER_SERVICE_ID" =~ ^srv- ]] || { echo "SERVICE_ID con formato raro (debe empezar srv-)"; ok=1; }

echo "[1/3] Probar acceso a /v1/services …"
code="$(curl -sS -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer ${RENDER_API_KEY}" \
  "https://api.render.com/v1/services?limit=1")" || true
echo "HTTP $code (esperado 200)"
[[ "$code" == "200" ]] || { echo "⇒ API KEY inválida o sin permisos"; exit 1; }

echo "[2/3] Ver detalles del servicio …"
det="$(curl -fsS -H "Authorization: Bearer ${RENDER_API_KEY}" \
  "https://api.render.com/v1/services/${RENDER_SERVICE_ID}")" || { echo "⇒ SERVICE_ID inválido o no accesible"; exit 1; }
echo "$det" | python - <<'PY'
import sys, json
s=json.load(sys.stdin).get("service",{})
print("name=", s.get("name"))
print("branch=", s.get("gitBranch"))
print("autoDeploy=", s.get("autoDeploy"))
PY

echo "[3/3] Últimos deploys (top 2) …"
curl -fsS -H "Authorization: Bearer ${RENDER_API_KEY}" \
 "https://api.render.com/v1/services/${RENDER_SERVICE_ID}/deploys?limit=2" | python - <<'PY'
import sys, json
for d in json.load(sys.stdin):
  print(d.get("id"), d.get("status"), d.get("createdAt"))
PY
