#!/usr/bin/env bash
set -euo pipefail
command -v gh >/dev/null || { echo "ERROR: faltó GitHub CLI (gh). Instalalo y logueate con 'gh auth login'"; exit 1; }

# Hook (recomendado; ya lo tenés en tu env)
if [[ -n "${RENDER_DEPLOY_HOOK:-}" ]]; then
  echo -n "$RENDER_DEPLOY_HOOK" | gh secret set RENDER_DEPLOY_HOOK --repo "$(git remote get-url origin | sed -E 's#.*github.com[:/](.+/.+)(\.git)?#\1#')" -b-
  echo "OK: secret RENDER_DEPLOY_HOOK seteado."
fi

# Si preferís API (opcional)
if [[ -n "${RENDER_API_KEY:-}" && -n "${RENDER_SERVICE_ID:-}" ]]; then
  echo -n "$RENDER_API_KEY"  | gh secret set RENDER_API_KEY  --repo "$(git remote get-url origin | sed -E 's#.*github.com[:/](.+/.+)(\.git)?#\1#')" -b-
  echo -n "$RENDER_SERVICE_ID" | gh secret set RENDER_SERVICE_ID --repo "$(git remote get-url origin | sed -E 's#.*github.com[:/](.+/.+)(\.git)?#\1#')" -b-
  echo "OK: secrets RENDER_API_KEY / RENDER_SERVICE_ID seteados."
fi
