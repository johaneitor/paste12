#!/usr/bin/env bash
set -euo pipefail
DEP="${1:?Uso: $0 dep-XXXXXXXXXXXX}"
: "${RENDER_API_KEY:?export RENDER_API_KEY=rnd_...}"
HOST="api.render.com"; PORT="443"
URL="https://${HOST}/v1/deploys/${DEP}"

code=000; body=""
while IFS= read -r ip; do
  body="$(curl -sS --resolve "${HOST}:${PORT}:${ip}" \
           -w '\n__HTTP:%{http_code}\n' \
           -H "Authorization: Bearer ${RENDER_API_KEY}" \
           -H "Accept: application/json" "$URL" || true)"
  code="$(printf '%s' "$body" | sed -n 's/^__HTTP:\([0-9][0-9][0-9]\)$/\1/p')"
  [ -n "$code" ] && break
done < <(tools/p12_doh_ips_v1.sh "$HOST")

json="$(printf '%s' "$body" | sed '/^__HTTP:/d')"
if [ "$code" != "200" ]; then
  echo "# GET /v1/deploys/$DEP → HTTP $code" >&2
  echo "# Body (primeras líneas):" >&2
  printf '%s\n' "$json" | sed -n '1,6p' >&2
  exit 0
fi

python - <<'PY' <<<"$json"
import json,sys
j=json.load(sys.stdin)
sid=j.get("serviceId") or ""
if sid: print(sid)
PY
