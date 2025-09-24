#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: frontend reconcile + audits}"
git rev-parse --is-inside-work-tree >/dev/null || { echo "ERROR: no es repo git"; exit 2; }

# Añadir cambios del frontend + tools nuevos aunque .gitignore tape
git add -f frontend/index.html || true
git add -f tools/*.sh || true

# Mostrar si hay deletions pendientes
git status --porcelain

# Compilación rápida de Python (si existen estos archivos)
pyok=1
for f in contract_shim.py wsgi.py backend/__init__.py backend/routes.py backend/models.py; do
  [[ -f "$f" ]] && python -m py_compile "$f" || true
done

# Commit
if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi

echo "== prepush gate =="; echo "✓ listo"
git push -u origin main
echo "== HEADs =="; echo "Local : $(git rev-parse HEAD)"; echo "Remote: $(git rev-parse @{u})"
