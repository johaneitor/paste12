#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: backend factory reset + routes + models + smoke}"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: no es repo git"; exit 2; }

# Gate sintaxis
bash -n tools/backend_factory_reset_v1.sh
bash -n tools/smoke_and_audit_factory_v1.sh

# Stage (forzado para tools)
git add -f tools/backend_factory_reset_v1.sh tools/smoke_and_audit_factory_v1.sh || true
git add backend/__init__.py backend/routes.py backend/models.py wsgi.py contract_shim.py 2>/dev/null || true
git add frontend/index.html frontend/privacy.html frontend/terms.html 2>/dev/null || true

if [[ -n "$(git status --porcelain)" ]]; then
  python -m py_compile backend/__init__.py backend/routes.py backend/models.py wsgi.py contract_shim.py
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi

echo "== prepush gate =="; echo "✓ listo"
git push -u origin main
echo "== HEADs =="; echo "Local : $(git rev-parse HEAD)"; echo "Remote: $(git rev-parse @{u})"
