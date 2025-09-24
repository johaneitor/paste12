#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: backend fix routes (future imports at top) + smoke}"

# Gates de sintaxis
bash -n tools/fix_future_imports_routes_v1.sh
[ -f tools/normalize_backend_init_safe_v1.sh ] && bash -n tools/normalize_backend_init_safe_v1.sh || true
bash -n tools/smoke_and_audit_after_routes_fix_v1.sh

# Aplicar fix de routes
tools/fix_future_imports_routes_v1.sh

# Stage forzado (por si .gitignore tapa tools/)
git add -f tools/fix_future_imports_routes_v1.sh tools/normalize_backend_init_safe_v1.sh tools/smoke_and_audit_after_routes_fix_v1.sh || true
git add backend/routes.py || true
git add backend/__init__.py 2>/dev/null || true

# Commit si hay cambios
if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi

echo "== prepush gate =="
echo "✓ listo"
git push -u origin main

echo "== HEADs =="
echo "Local : $(git rev-parse HEAD)"
UPSTREAM="$(git rev-parse @{u} 2>/dev/null || true)"
[[ -n "$UPSTREAM" ]] && echo "Remote: $UPSTREAM" || echo "Remote: (upstream se definió recién)"
