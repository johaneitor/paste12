#!/usr/bin/env bash
set -euo pipefail
HOOK="${RENDER_DEPLOY_HOOK:-}"
# Rechazar placeholders o basura
if [[ -z "$HOOK" || "$HOOK" =~ \<\<|^\<|^\> || ! "$HOOK" =~ ^https?:// ]]; then
  echo "SKIP: RENDER_DEPLOY_HOOK no válido. Usá plan B (git bump)." >&2
  exit 2
fi
curl -fsS -X POST "$HOOK" >/dev/null
echo "deploy hook disparado"
