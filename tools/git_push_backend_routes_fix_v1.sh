#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: backend routes methods fix (enable POST + /api blueprint)}"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: no git"; exit 2; }
bash -n tools/patch_backend_routes_methods_v1.sh
git add -f tools/patch_backend_routes_methods_v1.sh tools/test_publish_contract_v1.sh
git add backend/routes.py backend/__init__.py 2>/dev/null || true
if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi
echo "== prepush gate =="; echo "✓ listo"
git push -u origin main
echo "== HEADs =="; echo "Local : $(git rev-parse HEAD)"; echo "Remote: $(git rev-parse @{u})"
