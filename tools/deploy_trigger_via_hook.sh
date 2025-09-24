#!/usr/bin/env bash
set -euo pipefail
: "${RENDER_DEPLOY_HOOK:?RENDER_DEPLOY_HOOK no seteado}"
curl -fsS -X POST "$RENDER_DEPLOY_HOOK" >/dev/null
echo "Hook de deploy disparado."
