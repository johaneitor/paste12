#!/usr/bin/env bash
set -euo pipefail
paths=()
[ -f backend/static/index.html ] && paths+=(backend/static/index.html)
[ -f frontend/index.html ]       && paths+=(frontend/index.html)
[ ${#paths[@]} -eq 0 ] && { echo "✗ Nada para stagear"; exit 0; }
echo "Stageando: ${paths[*]}"
git add -f -- "${paths[@]}"
echo "== git status =="; git status --short || true
if git diff --cached --quiet; then
  echo "No hay cambios para commit."
else
  git commit -m "feat(frontend): safe-shim v1.1 (publish fallback, like/view delegados, auto-views, paginación keyset, nota única, nosw)"
  git push origin main
fi
