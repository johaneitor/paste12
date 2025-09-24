#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: backend core clean (no-cycles) + wsgi direct}"

# Gate básico
python -m py_compile backend/__init__.py backend/models.py backend/routes.py wsgi.py

# Stage (forzado por .gitignore)
git add -f tools/apply_clean_backend_core_v1.sh tools/smoke_core_backend_v1.sh tools/git_push_backend_core_v1.sh
git add backend/__init__.py backend/models.py backend/routes.py wsgi.py

# Commit/push
if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada que commitear"
fi
echo "== prepush =="
echo "✓ listo"
git push -u origin main

echo "Local : $(git rev-parse HEAD)"
UP="$(git rev-parse @{u} 2>/dev/null || true)"; [[ -n "$UP" ]] && echo "Remote: $UP" || true
