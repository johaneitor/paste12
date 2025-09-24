#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: backend consolidado + contrato estable v6}"
git add contract_shim.py wsgi.py || true
if [[ -f wsgiapp/__init__.py ]]; then git add wsgiapp/__init__.py || true; fi
if [[ -f backend/routes.py ]];   then git add backend/routes.py || true; fi
git status --porcelain
if git diff --cached --quiet; then
  echo "ℹ️  Nada que commitear"
else
  git commit -m "$MSG"
fi
echo "== prepush gate =="
python -m py_compile contract_shim.py wsgi.py || true
git push origin main
