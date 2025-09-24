#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: fix backend (POST /api/notes + CORS + blueprint)}"

git add -f tools/patch_post_and_cors_v1.sh || true
git add backend/__init__.py backend/routes.py 2>/dev/null || true

if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi

echo "== prepush =="
echo "✓ listo"
git push -u origin main
echo "Local : $(git rev-parse HEAD)"
echo "Remote: $(git rev-parse @{u})"
