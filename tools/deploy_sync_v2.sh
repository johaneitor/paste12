#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL}"
echo "== probe =="
if tools/deploy_probe_v2.sh "$BASE"; then
  echo "Deploy ya alineado."; exit 0
fi
echo "== trigger =="
# 1) Si hay hook válido, lo usamos; si no, git bump
if tools/deploy_trigger_via_hook_safe.sh; then
  :
else
  tools/deploy_trigger_via_git_bump_v2.sh
fi
echo "== watch =="
tools/deploy_watch_until_v6.sh "$BASE" 480
# Verificación final
tools/deploy_probe_v2.sh "$BASE"
