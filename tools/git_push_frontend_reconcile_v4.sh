#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: frontend reconcile v4 (adsense+views+seo+dedupe+no-sw)}"

# Gates de sintaxis básicos de los scripts
bash -n tools/frontend_reconcile_v4.sh

# Stage forzado (por .gitignore de tools/)
git add -f tools/frontend_reconcile_v4.sh || true
# Index y páginas legales si cambiaron
git add frontend/index.html 2>/dev/null || true
git add frontend/terms.html 2>/dev/null || true
git add frontend/privacy.html 2>/dev/null || true

if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi

echo "== prepush =="
echo "✓ listo"
git push -u origin main

echo "== HEADs =="
echo "Local : $(git rev-parse HEAD)"
UP="$(git rev-parse @{u} 2>/dev/null || true)"
[[ -n "$UP" ]] && echo "Remote: $UP" || echo "Remote: (upstream recién seteado)"
