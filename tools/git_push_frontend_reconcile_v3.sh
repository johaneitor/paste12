#!/usr/bin/env bash
# Uso: tools/git_push_frontend_reconcile_v3.sh "ops: frontend reconcile v4"
set -euo pipefail
MSG="${1:-ops: frontend reconcile v4 (h1 dedup + adsense + stats + nosw + seo)}"

git rev-parse --is-inside-work-tree >/dev/null || { echo "ERROR: no es repo git"; exit 2; }

# Stage forzado (por .gitignore de tools/)
git add -f tools/frontend_reconcile_v4.sh 2>/dev/null || true
[[ -f frontend/index.html ]] && git add frontend/index.html

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
[[ -n "$UP" ]] && echo "Remote: $UP" || echo "Remote: (upstream definido recién)"
