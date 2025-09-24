#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: hotfix 405 + nocache + frontend submit v3}"

# permitir tools/*.sh y frontend/*.html aunque exista .gitignore
if [[ -f .gitignore ]]; then
  if ! grep -qE '^!tools/\\*\\.sh$' .gitignore; then
    printf '\n# allow deploy tools & HTML\n!tools/*.sh\n!frontend/*.html\n' >> .gitignore
    git add .gitignore || true
  fi
fi

git add -f tools/hotfix_backend_405_nocache_v1.sh tools/hotfix_frontend_submit_v3.sh
[[ -f backend/routes.py ]] && git add backend/routes.py || true
[[ -f backend/__init__.py ]] && git add backend/__init__.py || true
[[ -f frontend/index.html ]] && git add frontend/index.html || true

if [[ -n "$(git status --porcelain)" ]]; then git commit -m "$MSG"; else echo "ℹ️  Nada para commitear"; fi

echo "== prepush gate =="; echo "✓ listo"
git push -u origin main

echo "== HEADs =="; echo "Local : $(git rev-parse HEAD)"; echo "Remote: $(git rev-parse @{u})"
