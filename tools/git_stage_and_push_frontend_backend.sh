#!/usr/bin/env bash
set -euo pipefail
paths=()
[ -f backend/static/index.html ] && paths+=(backend/static/index.html)
[ -f frontend/index.html ]       && paths+=(frontend/index.html)
[ -f wsgiapp/__init__.py ]       && paths+=(wsgiapp/__init__.py)
[ -f tools/patch_frontend_consolidated_v6.py ] && paths+=(tools/patch_frontend_consolidated_v6.py)
[ ${#paths[@]} -eq 0 ] && { echo "✗ Nada para stagear"; exit 0; }

echo "Stageando: ${paths[*]}"
git add -f -- "${paths[@]}"
echo "== git status =="; git status --short || true

if git diff --cached --quiet; then
  echo "No hay cambios para commit."
else
  git commit -m "fix: indent backend + frontend v6 (botones, vistas, publicar fallback, paginación, nota única, banner off)"
  git push origin main
fi
