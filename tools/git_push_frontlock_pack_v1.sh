#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: front-lock serve + reconcile (adsense+views)}}"

# Asegurar repo
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: no es repo git"; exit 2; }

# Stage (forzado por .gitignore)
git add -f tools/frontend_reconcile_v3.sh tools/lock_frontend_serve_in_shim_v1.sh tools/smoke_and_audit_frontend_lock_v1.sh 2>/dev/null || true
git add -f tools/git_push_frontlock_pack_v1.sh 2>/dev/null || true
git add frontend/index.html frontend/privacy.html frontend/terms.html 2>/dev/null || true
git add contract_shim.py 2>/dev/null || true

# Commit si hay cambios
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
UP="$(git rev-parse @{u} 2>/dev/null || true)"; [[ -n "$UP" ]] && echo "Remote: $UP" || true
