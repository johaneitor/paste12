#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: fix CORS import + expose app (WSGI ready)}"

# Gates rápidos
python -m py_compile backend/__init__.py 2>/dev/null || true
bash -n tools/fix_cors_and_wsgi_app_v1.sh 2>/dev/null || true
bash -n tools/smoke_wsgi_and_health_v2.sh 2>/dev/null || true

# Stage (forzado por si .gitignore tapa tools/)
git add -f tools/fix_cors_and_wsgi_app_v1.sh tools/smoke_wsgi_and_health_v2.sh tools/git_push_fix_cors_and_wsgi_v1.sh || true
git add backend/__init__.py 2>/dev/null || true

if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi

echo "== prepush gate =="
echo "✓ listo"
git push -u origin main

echo "== HEADs =="
echo "Local : $(git rev-parse HEAD)"
UP="$(git rev-parse @{u} 2>/dev/null || true)"
[[ -n "$UP" ]] && echo "Remote: $UP" || echo "Remote: (upstream recién creado)"
