#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: factory_min_fix + smoke_circuit_v8}"

# Forzamos incluir tools/ y archivos clave
git add -f backend/__init__.py backend/routes.py backend/routes_api_min.py wsgi.py \
        tools/factory_min_fix_v1.sh tools/smoke_circuit_v8.sh tools/git_push_min_factory_v1.sh

# Commit si hay cambios
if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi

echo "== prepush: py_compile =="
python -m py_compile backend/__init__.py wsgi.py && echo "py_compile OK"

echo "== pushing =="
git push -u origin main
