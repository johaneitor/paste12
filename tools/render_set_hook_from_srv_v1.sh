#!/usr/bin/env bash
set -euo pipefail
SRV="${1:?Uso: $0 srv-XXXXXXXXXXXX}"
KEY="${2:-<<TU_KEY>>}"  # si ya la tenés, pasala acá
echo "export RENDER_SERVICE_ID=\"$SRV\""
echo "export RENDER_DEPLOY_HOOK=\"https://api.render.com/deploy/${SRV}?key=${KEY}\""
