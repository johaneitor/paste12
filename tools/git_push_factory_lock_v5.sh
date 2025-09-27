#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: backend factory lock v5 (health first + safe fallback + wsgi)}"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: no es repo git"; exit 2; }

python -m py_compile backend/__init__.py wsgi.py && echo "✓ py_compile OK"

git add -f backend/__init__.py wsgi.py tools/backend_factory_lock_v5.sh tools/smoke_after_factory_lock_v5.sh
git commit -m "$MSG" || echo "ℹ️  nada que commitear"
echo "== prepush =="
echo "✓ listo"
git push -u origin main
