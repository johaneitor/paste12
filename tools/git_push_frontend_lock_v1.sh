#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: frontend lock serve (index/terms/privacy del repo) + auditoría}"

# Gate rápido
bash -n tools/fix_frontend_serve_lock_v1.sh

# Stage forzado de tools y backend
git add -f tools/fix_frontend_serve_lock_v1.sh || true
git add backend/front_serve.py backend/__init__.py || true
git add frontend/index.html frontend/terms.html frontend/privacy.html 2>/dev/null || true

if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi

echo "== prepush =="
python -m py_compile backend/front_serve.py backend/__init__.py || { echo "py_compile FAIL"; exit 3; }
echo "✓ py_compile OK"

git push -u origin main

echo "== HEADs =="
echo "Local : $(git rev-parse HEAD)"
echo "Remote: $(git rev-parse @{u})"
