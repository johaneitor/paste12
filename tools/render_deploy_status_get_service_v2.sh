#!/usr/bin/env bash
set -euo pipefail
DEP="${1:?Uso: $0 dep-XXXXXXXXXXXX}"
: "${RENDER_API_KEY:?export RENDER_API_KEY=rnd_...}"
HOST="api.render.com"; PORT="443"
URL="https://${HOST}/v1/deploys/${DEP}"
doh_ips(){ for u in "https://1.1.1.1/dns-query?name=${HOST}&type=A" "https://1.0.0.1/dns-query?name=${HOST}&type=A"; do
  curl -sS -H 'accept: application/dns-json' "$u" | sed -n 's/.*"data":"\([0-9.]\+\)".*/\1/p'
done | sort -u; }
code=000; body=""
for ip in $(doh_ips); do
  body="$(curl -sS --resolve "${HOST}:${PORT}:${ip}" -w '\n__HTTP:%{http_code}\n' -H "Authorization: Bearer ${RENDER_API_KEY}" -H "Accept: application/json" "$URL")" || true
  code="$(printf '%s' "$body" | sed -n 's/^__HTTP:\([0-9][0-9][0-9]\)$/\1/p')"
  [ -n "$code" ] && break
done
json="$(printf '%s' "$body" | sed '/^__HTTP:/d')"
if [ "$code" != "200" ]; then
  echo "# GET /v1/deploys/$DEP → HTTP $code" >&2
  echo "# Body (primeras líneas):" >&2
  printf '%s\n' "$json" | sed -n '1,4p' >&2
  echo ""  # stdout vacío para que el caller lo detecte
  exit 0
fi
python - <<'PY' <<<"$json"
import sys,json
j=json.load(sys.stdin)
sid=j.get("serviceId") or ""
if sid: print(sid)
PY
