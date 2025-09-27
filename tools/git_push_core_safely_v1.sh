#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: core + tests (circuit v3)}"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: no es repo git"; exit 2; }

# Stage cambios clave y scripts nuevos
git add -f tools/circuit_test_suite_v3.sh 2>/dev/null || true
# (añade aquí otros tools/ que quieras empujar)

# Sanity py_compile si existen estos archivos
py_ok=1
for f in backend/__init__.py backend/routes.py wsgi.py contract_shim.py; do
  [[ -f "$f" ]] && python -m py_compile "$f" || true
done

# Commit si hay cambios
if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi

# Push
git push -u origin main
echo "== HEAD =="
git rev-parse HEAD
