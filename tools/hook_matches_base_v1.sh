#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL}"
: "${RENDER_DEPLOY_HOOK:?export RENDER_DEPLOY_HOOK=https://api.render.com/deploy/srv-...?...}"
: "${RENDER_API_KEY:?export RENDER_API_KEY=rnd_...}"
HOST="api.render.com"; PORT="443"
SID="$(echo "$RENDER_DEPLOY_HOOK" | sed -n 's#.*deploy/\(srv-[a-z0-9]\+\)\?.*#\1#p')"
[ -n "$SID" ] || { echo "ERROR: no pude extraer srv- del HOOK"; exit 2; }

# resolver DoH robusto (una IP por línea)
doh_ips(){ 
  {
    curl -sS -H 'accept: application/dns-json' "https://1.1.1.1/dns-query?name=${HOST}&type=A" || true
    echo
    curl -sS -H 'accept: application/dns-json' "https://1.0.0.1/dns-query?name=${HOST}&type=A" || true
  } | tr ',' '\n' | sed -n 's/.*"data":"\([0-9.]\+\)".*/\1/p' | awk '!seen[$0]++'
}

# GET service
CODE=000; BODY=""
while IFS= read -r ip; do
  BODY="$(curl -sS --resolve "${HOST}:${PORT}:${ip}" \
    -w '\n__HTTP:%{http_code}\n' \
    -H "Authorization: Bearer ${RENDER_API_KEY}" -H "Accept: application/json" \
    "https://${HOST}/v1/services/${SID}" || true)"
  CODE="$(printf '%s' "$BODY" | sed -n 's/^__HTTP:\([0-9][0-9][0-9]\)$/\1/p')"
  [ -n "$CODE" ] && break
done < <(doh_ips)

JSON="$(printf '%s' "$BODY" | sed '/^__HTTP:/d')"
if [ "$CODE" != "200" ]; then
  echo "HOOK srv=${SID} → API HTTP $CODE (no se pudo inspeccionar)"; exit 3
fi

# Parseo clave
python - "$BASE" <<'PY' <<<"$JSON"
import json,sys
svc=json.load(sys.stdin); base=sys.argv[1].rstrip('/')
url=(svc.get("url") or "").rstrip('/')
repo=svc.get("repo"); branch=svc.get("branch"); name=svc.get("name")
print(f"service.id: {svc.get('id')}")
print(f"service.name: {name}")
print(f"service.url: {url or 'None'}")
print(f"service.repo: {repo}")
print(f"service.branch: {branch}")
ok = (url == base) if url else False
print("MATCH:", "YES" if ok else "NO")
PY
