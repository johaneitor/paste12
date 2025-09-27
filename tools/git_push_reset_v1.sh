#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: hard reset backend factory v6 + safe HTTPException handling + smoke}"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "No es repo git"; exit 2; }
bash -n tools/hard_reset_backend_factory_v6.sh
bash -n tools/smoke_after_reset_v1.sh
git add -f backend/__init__.py tools/hard_reset_backend_factory_v6.sh tools/smoke_after_reset_v1.sh
if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada que commitear"
fi
echo "== prepush py_compile =="
python -m py_compile backend/__init__.py && echo "OK"
git push -u origin main
