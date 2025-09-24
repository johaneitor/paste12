#!/usr/bin/env bash
set -euo pipefail
paths=()
[ -f backend/static/index.html ] && paths+=(backend/static/index.html)
[ -f frontend/index.html ]       && paths+=(frontend/index.html)
# incluir los smokes nuevos
[ -f tools/smoke_ui_like_view_share_v4.sh ] && paths+=(tools/smoke_ui_like_view_share_v4.sh)

if [ ${#paths[@]} -eq 0 ]; then echo "✗ Nada para stagear"; exit 0; fi
echo "Stageando: ${paths[*]}"
git add -f -- "${paths[@]}"
echo "== git status =="; git status --short || true

if git diff --cached --quiet; then
  echo "No hay cambios para commit."
else
  git commit -m "chore(frontend): smoke v4 (single-page flags) y assets consolidados"
  git push origin main
fi
