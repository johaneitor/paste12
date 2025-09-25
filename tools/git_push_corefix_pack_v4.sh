#!/usr/bin/env bash
set -euo pipefail

MSG="${1:-ops: corefix — front routes + api fallback + no-store}"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: no es repo git"; exit 2; }

# 0) Sanity Python
echo "== py_compile =="
python -m py_compile backend/__init__.py || { echo "py_compile FAIL"; exit 3; }

# 1) Stage archivos relevantes
git add -f backend/__init__.py tools/fix_backend_fallback_and_front_v1.sh 2>/dev/null || true

# 2) Commit si hay cambios
if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi

# 3) Push
echo "== PUSH =="
git push -u origin main

# 4) Info
echo "== HEAD =="
git rev-parse HEAD
