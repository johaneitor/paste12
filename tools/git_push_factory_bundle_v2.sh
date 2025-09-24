#!/usr/bin/env bash
set -euo pipefail

MSG="${1:-ops: backend factory reset + models + routes + smoke runner}"

# 0) Chequeos básicos
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: no es repo git"; exit 2; }

# 1) Gates de sintaxis de los scripts
[[ -f tools/backend_factory_reset_v1.sh ]] && bash -n tools/backend_factory_reset_v1.sh || true
[[ -f tools/smoke_and_audit_factory_v1.sh ]] && bash -n tools/smoke_and_audit_factory_v1.sh || true

# 2) Stage (forzado para tools por si .gitignore los tapa)
git add -f tools/backend_factory_reset_v1.sh 2>/dev/null || true
git add -f tools/smoke_and_audit_factory_v1.sh 2>/dev/null || true

# 3) Stage de código backend y frontend esenciales
git add backend/__init__.py backend/routes.py backend/models.py wsgi.py contract_shim.py 2>/dev/null || true
git add frontend/index.html frontend/privacy.html frontend/terms.html 2>/dev/null || true

# 4) Commit solo si hay cambios
if [[ -n "$(git status --porcelain)" ]]; then
  # Sanity Python
  python -m py_compile backend/__init__.py backend/routes.py backend/models.py wsgi.py contract_shim.py
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi

# 5) Push
echo "== prepush gate =="; echo "✓ listo"
git push -u origin main

# 6) SHAs
echo "== HEADs ==" 
echo "Local : $(git rev-parse HEAD)"
UP="$(git rev-parse @{u} 2>/dev/null || true)"
[[ -n "$UP" ]] && echo "Remote: $UP" || echo "Remote: (upstream recién configurado)"
