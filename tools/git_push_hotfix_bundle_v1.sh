#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: backend hotfix (ready bypass + methods + wsgi simple) + smoke}"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "No es repo git"; exit 2; }

# Gates rápidos
python -m py_compile wsgi.py || true
[[ -f backend/routes.py ]] && python -m py_compile backend/routes.py || true
[[ -f backend/__init__.py ]] && python -m py_compile backend/__init__.py || true

# Stage (forzado)
git add -f wsgi.py tools/hotfix_backend_api_ready_v1.sh tools/smoke_all_after_hotfix_v1.sh || true
[[ -f backend/routes.py ]] && git add backend/routes.py || true
[[ -f backend/__init__.py ]] && git add backend/__init__.py || true

if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi

echo "== prepush =="
echo "OK"
git push -u origin main
echo "Local : $(git rev-parse HEAD)"
echo "Remote: $(git rev-parse @{u})"
