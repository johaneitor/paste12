#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR]}"
OUTDIR="${2:-/sdcard/Download}"
API_KEY="${RENDER_API_KEY:?export RENDER_API_KEY=...}"
SERVICE_ID="${RENDER_SERVICE_ID:?export RENDER_SERVICE_ID=srv_...}"
HOST="api.render.com"; PORT="443"

doh_ips(){
  for u in \
    "https://1.1.1.1/dns-query?name=${HOST}&type=A" \
    "https://1.0.0.1/dns-query?name=${HOST}&type=A"
  do
    curl -sS -H 'accept: application/dns-json' "$u" \
    | grep -oE '"data":"([0-9]{1,3}\.){3}[0-9]{1,3}"' \
    | cut -d':' -f2 | tr -d '"'
  done | sort -u
}

api_post(){
  local url="$1" body="${2:-{}}"
  local ok=1
  while IFS= read -r ip; do
    if curl -sS --resolve "${HOST}:${PORT}:${ip}" -X POST \
        -H "Authorization: Bearer ${API_KEY}" \
        -H "Content-Type: application/json" \
        -d "$body" "$url" -o /dev/null; then
      ok=0; break
    fi
  done <<<"$(doh_ips)"
  return $ok
}

echo "== API: crear deploy =="
api_post "https://${HOST}/v1/services/${SERVICE_ID}/deploys" "{}" \
  || { echo "ERROR: no pude crear el deploy via API"; exit 2; }
echo "OK: deploy creado"

echo "== Watch remoto==local =="
tools/deploy_watch_until_v7.sh "$BASE" 900

echo "== Auditorías =="
tools/audit_remote_deep_v4.sh "$BASE" "$OUTDIR" >/dev/null || true
tools/live_vs_local_v1.sh     "$BASE" "$OUTDIR" >/dev/null || true
tools/audit_full_stack_v3.sh  "$BASE" "$OUTDIR" >/dev/null || true
echo "Listo. Artefactos en $OUTDIR"
