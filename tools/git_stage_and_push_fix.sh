#!/usr/bin/env bash
set -euo pipefail
paths=()
[ -f wsgiapp/__init__.py ] && paths+=(wsgiapp/__init__.py)
[ -f backend/static/index.html ] && paths+=(backend/static/index.html)
[ -f frontend/index.html ] && paths+=(frontend/index.html)
[ -f tools/canon_routes_block_v3.py ] && paths+=(tools/canon_routes_block_v3.py)
echo "Stageando: ${paths[*]}"; git add -f -- "${paths[@]}"
echo "== git status =="; git status --short || true
if git diff --cached --quiet; then
  echo "No hay cambios para commit."
else
  git commit -m "fix(wsgi): canoniza bloque de rutas (/, terms, privacy, health, OPTIONS) y normaliza indent"
  git push origin main
fi
