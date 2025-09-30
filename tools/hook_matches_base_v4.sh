#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL}"
: "${RENDER_DEPLOY_HOOK:?export RENDER_DEPLOY_HOOK=https://api.render.com/deploy/srv-...?...}"
: "${RENDER_API_KEY:?export RENDER_API_KEY=rnd_...}"
HOST="api.render.com"; PORT="443"
SID="$(echo "$RENDER_DEPLOY_HOOK" | sed -n 's#.*deploy/\(srv-[a-z0-9]\+\)\?.*#\1#p')"
[ -n "$SID" ] || { echo "ERROR: no pude extraer srv- del HOOK"; exit 0; }

tools/p12_doh_ips_v1.sh "${HOST}" >/dev/null 2>&1 || {
  echo "ERROR: falta tools/p12_doh_ips_v1.sh"; exit 0;
}

TMPDIR="${HOME}/.cache/p12"; mkdir -p "$TMPDIR"
RESP="$TMPDIR/service-${SID}.json"

ok=1
while IFS= read -r ip; do
  if curl -sS --resolve "${HOST}:${PORT}:${ip}" \
      -H "Authorization: Bearer ${RENDER_API_KEY}" \
      -H "Accept: application/json" \
      "https://${HOST}/v1/services/${SID}" -o "$RESP"; then ok=0; break; fi
done < <(tools/p12_doh_ips_v1.sh "$HOST")
[ $ok -eq 0 ] || { echo "ERROR: no pude inspeccionar el servicio ${SID}"; exit 0; }

python - "$BASE" "$RESP" <<'PY'
import sys,json,urllib.parse
base=sys.argv[1].rstrip('/')
j=json.load(open(sys.argv[2],'r',encoding='utf-8'))

# Render: la URL pública suele venir en serviceDetails.url
sd = j.get('serviceDetails') or {}
url = (j.get('url') or sd.get('url') or '').rstrip('/')

# También considerar customDomains / aliases
def host(u):
    try: return urllib.parse.urlparse(u).netloc.lower()
    except: return ''
base_host = host(base)
url_host  = host(url)
customs = [ (('https://'+d).rstrip('/')) for d in (sd.get('customDomains') or []) ]
custom_hosts = [host(u) for u in customs]

match = False
reason = ""
if url and url==base:
    match=True; reason="by_url_exact"
elif url_host and base_host and url_host==base_host:
    match=True; reason="by_host_equal"
elif base_host and base_host in custom_hosts:
    match=True; reason="by_custom_domain"

print(f"service.id: {j.get('id')}")
print(f"service.name: {j.get('name')}")
print(f"service.url: {url or 'None'}")
print(f"service.repo: {j.get('repo')}")
print(f"service.branch: {j.get('branch')}")
print(f"service.customDomains: {', '.join(customs) if customs else '[]'}")
print("MATCH:", "YES" if match else "NO", reason)
PY
