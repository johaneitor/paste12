#!/usr/bin/env bash
set -euo pipefail
: "${1:?Uso: $0 https://<tu-servicio>.onrender.com}"
BASE="$1"
: "${RENDER_API_KEY:?export RENDER_API_KEY=...}"
HOST="api.render.com"; PORT="443"
URL="https://${HOST}/v1/services?limit=200"

doh_ips(){ for u in "https://1.1.1.1/dns-query?name=${HOST}&type=A" "https://1.0.0.1/dns-query?name=${HOST}&type=A"; do
  curl -sS -H 'accept: application/dns-json' "$u" \
  | grep -oE '"data":"([0-9]{1,3}\.){3}[0-9]{1,3}"' | cut -d':' -f2 | tr -d '"'
done | sort -u; }

fetch_json(){ 
  while IFS= read -r ip; do
    curl -sS --resolve "${HOST}:${PORT}:${ip}" \
      -H "Authorization: Bearer ${RENDER_API_KEY}" -H "Accept: application/json" \
      "$URL" && return 0
  done < <(doh_ips)
  return 1
}

json="$(fetch_json)" || { echo "ERROR: no pude listar servicios (API)"; exit 2; }

P12_JSON="$json" P12_BASE="$BASE" python - <<'PY'
import os, json, sys
base=os.environ['P12_BASE'].strip().rstrip('/')
arr=json.loads(os.environ['P12_JSON'])
match=[s for s in arr if (s.get("url") or "").rstrip('/')==base]
if not match:
    print("echo 'ERROR: no encontré service con url=%s' >&2; exit 2" % base)
else:
    srv=match[0]
    print('export RENDER_SERVICE_ID="%s"' % srv.get("id"))
    print('echo "OK: service %s (%s) → %s branch=%s"' % (srv.get("id"), srv.get("name"), srv.get("repo"), srv.get("branch")))
PY
