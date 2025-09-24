#!/usr/bin/env bash
set -euo pipefail
paths=()
for f in backend/static/index.html frontend/index.html index.html; do
  [ -f "$f" ] && paths+=("$f")
done
# incluye los helpers nuevos
for f in tools/patch_frontend_cohesion_safe.sh tools/rollback_frontend_cohesion.sh tools/smoke_ui_publish_pagination.sh; do
  [ -f "$f" ] && paths+=("$f")
done
if [ ${#paths[@]} -eq 0 ]; then
  echo "✗ Nada para stagear"; exit 0
fi
echo "Stageando: ${paths[*]}"
git add -f -- "${paths[@]}"
echo "== git status =="
git status --short
if git diff --cached --quiet; then
  echo "No hay cambios para commit."
else
  git commit -m "feat(frontend): shim de cohesión (unificación feed, ver más, paginación keyset, nosw) + scripts"
  git push origin main
fi
