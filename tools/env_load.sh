#!/usr/bin/env bash
set -euo pipefail
[[ -f .env ]] && set -a && . ./.env && set +a
: "${BASE:?Definí BASE, ej: https://paste12-rmsk.onrender.com}"
export BASE RENDER_DEPLOY_HOOK="${RENDER_DEPLOY_HOOK:-}"
