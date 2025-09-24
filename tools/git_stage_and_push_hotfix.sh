#!/usr/bin/env bash
set -euo pipefail
paths=(wsgiapp/__init__.py tools/repair_wsgi_finish_and_index_guard.py)
echo "Stageando: ${paths[*]}"
git add -f -- "${paths[@]}"
echo "== git status =="; git status --short || true
if git diff --cached --quiet; then
  echo "No hay cambios para commit."
else
  git commit -m "hotfix(wsgi): _finish robusto + guard index (evita 200 con body vacío y restituye index)"
  git push origin main
fi
