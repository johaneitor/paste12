#!/usr/bin/env bash
set -euo pipefail
if [[ -z "${RENDER_DEPLOY_HOOK:-}" ]]; then
  echo "ERROR: falta RENDER_DEPLOY_HOOK. Usá el plan B: tools/deploy_trigger_via_git_bump.sh" >&2
  exit 2
fi
curl -fsS -X POST "$RENDER_DEPLOY_HOOK" >/dev/null
echo "deploy hook disparado"
