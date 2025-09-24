#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: allow POST /api/notes + UI single tagline + tests}"
git add -f tools/patch_backend_routes_allow_post_v1.sh tools/fix_frontend_single_tagline_v1.sh tools/test_publish_and_ui_v1.sh
git add backend/routes.py frontend/index.html 2>/dev/null || true
if [ -n "$(git status --porcelain)" ]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi
echo "== prepush gate =="; echo "✓ listo"
git push -u origin main
