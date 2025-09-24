#!/usr/bin/env bash
set -euo pipefail

# Rutas candidatas que realmente existen
paths=()
[ -f backend/static/index.html ] && paths+=(backend/static/index.html)
[ -f frontend/index.html ]       && paths+=(frontend/index.html)
[ -f index.html ]                && paths+=(index.html)

# Si tocaste el backend (no es obligatorio)
[ -f wsgiapp/__init__.py ]       && paths+=(wsgiapp/__init__.py)

if [ ${#paths[@]} -eq 0 ]; then
  echo "✗ No hay archivos que agregar (nada que stagear)."
  exit 0
fi

echo "Stageando: ${paths[*]}"
git add -f -- "${paths[@]}"

echo "== git status =="
git status --short

# Commit si hay cambios
if ! git diff --cached --quiet; then
  git commit -m "chore(frontend): banner de versión basado en /api/deploy-stamp (y staging robusto)"
  git push origin main
else
  echo "No hay cambios en el index para commitear."
fi
