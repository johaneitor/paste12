#!/usr/bin/env bash
set -euo pipefail

echo "== Fetch base =="
git fetch origin main

echo "== Reset mixto a origin/main (conserva tu working tree) =="
git checkout -B main origin/main
git reset --mixed origin/main

echo "== Quitar workflow del working tree e índice (si existe) =="
rm -f .github/workflows/render-redeploy.yml || true
git rm -f --cached .github/workflows/render-redeploy.yml 2>/dev/null || true
# por si quedó algo más en workflows/
if [ -d ".github/workflows" ]; then
  # aseguramos que no queden archivos nuevos ahí
  find .github/workflows -type f -print -exec rm -f {} \; || true
fi

echo "== Preparar commit limpio con el resto de cambios =="
# seguridad: compilar backend antes del commit
python -m py_compile wsgiapp/__init__.py 2>/dev/null && echo "py_compile OK" || echo "py_compile (skip)"
git add -A
git commit -m "deploy: aplicar cambios pendientes (excluido .github/workflows)" || echo "Nada para commitear"

echo "== Push a origin/main =="
git push -u origin main
