#!/usr/bin/env bash
set -euo pipefail
HOOK="${RENDER_DEPLOY_HOOK:-}"
API_KEY="${RENDER_API_KEY:-}"
SERVICE_ID="${RENDER_SERVICE_ID:-}"

good_url='^https?://'
use_hook=false
if [[ -n "$HOOK" && "$HOOK" =~ $good_url && "$HOOK" != *"<<"* && "$HOOK" != *">>"* ]]; then
  use_hook=true
fi

if $use_hook; then
  echo "→ Disparando deploy via hook…"
  curl -fsS -X POST "$HOOK" >/dev/null
  echo "OK: deploy hook enviado."
  exit 0
fi

if [[ -n "$API_KEY" && -n "$SERVICE_ID" ]]; then
  echo "→ Disparando deploy via API (Render)…"
  # Nota: no usamos -f para mostrar cualquier 4xx/5xx
  curl -sS -X POST \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d '{}' \
    "https://api.render.com/v1/services/$SERVICE_ID/deploys"
  echo
  echo "OK: solicitud de deploy enviada a la API."
  exit 0
fi

cat <<MSG >&2
ERROR: No hay forma de disparar el deploy.
Seteá UNA de estas opciones y reintentá:

1) Deploy Hook:
   export RENDER_DEPLOY_HOOK="https://api.render.com/deploy/srv-xxxx?key=yyyy"

   (copialo de Render > Service > Settings > Deploy Hook)

— o —

2) API:
   export RENDER_API_KEY="rxxxxxxxxxxxxxxxxxxxx"
   export RENDER_SERVICE_ID="srv-xxxxxxxxxxxx"

   (Render > Dashboard > API Keys y el Service ID en la URL del servicio)
MSG
exit 2
