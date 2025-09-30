#!/usr/bin/env bash
set -euo pipefail
HOOK="${RENDER_DEPLOY_HOOK:-}"
API_KEY="${RENDER_API_KEY:-}"
SERVICE_ID="${RENDER_SERVICE_ID:-}"
HOST="api.render.com"
PORT="443"

doh_ips(){
  # Intenta Cloudflare DoH por IP (sin resolver DNS)
  # Devuelve una lista de IPs A separadas por espacios
  for doh in "https://1.1.1.1/dns-query?name=${HOST}&type=A" "https://1.0.0.1/dns-query?name=${HOST}&type=A"; do
    ips="$(curl -sS -H 'accept: application/dns-json' "$doh" \
      | sed -n 's/.*"data":"\([0-9]\{1,3\}\(\.[0-9]\{1,3\}\)\{3\}\)".*/\1/p' \
      | tr '\n' ' ' | xargs)"
    if [[ -n "$ips" ]]; then echo "$ips"; return 0; fi
  done
  echo ""
}

curl_resolve_post(){
  local url="$1"; shift
  local ips; ips="$(doh_ips)"
  if [[ -z "$ips" ]]; then
    echo "ERROR: No pude resolver $HOST vía DoH (1.1.1.1). Seteá RENDER_DEPLOY_HOOK o API y reintentá." >&2
    return 2
  fi
  for ip in $ips; do
    # Forzar SNI correcto con --resolve (TLS para HOST, pero conectando a IP)
    if curl -sS -X POST --resolve "${HOST}:${PORT}:${ip}" "$url" -o /dev/null; then
      echo "OK: hook enviado via ${ip}"
      return 0
    fi
  done
  echo "ERROR: no pude POSTear al hook usando --resolve con IPs: $ips" >&2
  return 3
}

curl_resolve_api(){
  # POST /v1/services/:id/deploys con Bearer API_KEY
  local api_url="https://${HOST}/v1/services/${SERVICE_ID}/deploys"
  local ips; ips="$(doh_ips)"
  [[ -z "$ips" ]] && { echo "ERROR: DoH no devolvió IPs para ${HOST}"; return 2; }
  for ip in $ips; do
    if curl -sS -X POST \
      --resolve "${HOST}:${PORT}:${ip}" \
      -H "Authorization: Bearer ${API_KEY}" \
      -H "Content-Type: application/json" \
      -d '{}' \
      "$api_url" -o /dev/null; then
      echo "OK: API deploy creado via ${ip}"
      return 0
    fi
  done
  echo "ERROR: no pude crear deploy vía API usando --resolve" >&2
  return 3
}

if [[ -n "$HOOK" && "$HOOK" != *'<<'* && "$HOOK" != *'>>'* ]]; then
  echo "→ Disparando deploy via HOOK (DoH)…"
  curl_resolve_post "$HOOK"
  exit $?
fi

if [[ -n "$API_KEY" && -n "$SERVICE_ID" ]]; then
  echo "→ Disparando deploy via API (DoH)…"
  curl_resolve_api
  exit $?
fi

cat <<MSG >&2
ERROR: Falta configuración para disparar el deploy.
Seteá UNA opción y reintentá:

1) Hook:
   export RENDER_DEPLOY_HOOK=export RENDER_DEPLOY_HOOK="https://api.render.com/deploy/srv-d2hb193uibrs73f421fg?key=BTN64h3FRXw"

o 2) API:
   export RENDER_API_KEY="r_XXXXXXXXXXXXXXXX"
   export RENDER_SERVICE_ID="srv-XXXXXXXXXXXX"
MSG
exit 2
