#!/usr/bin/env bash
set -euo pipefail
paths=()
[ -f wsgiapp/__init__.py ] && paths+=(wsgiapp/__init__.py)
[ -f backend/static/index.html ] && paths+=(backend/static/index.html)
[ -f frontend/index.html ] && paths+=(frontend/index.html)
[ ${#paths[@]} -eq 0 ] && { echo "✗ nada para stagear"; exit 0; }
echo "Stageando: ${paths[*]}"
git add -f -- "${paths[@]}"
echo "== git status =="; git status --short || true
if git diff --cached --quiet; then
  echo "No hay cambios para commit."
else
  git commit -m "fix: backend rutas+single + frontend v7 mini-shim (publish fallback, botones, paginación, single)"
  git push origin main
fi
