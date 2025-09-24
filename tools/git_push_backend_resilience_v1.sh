#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: backend resilience (pool+retry) v1}"

git add -f tools/fix_backend_indent_and_pool_v1.sh tools/patch_routes_retry_db_v1.sh tools/test_backend_contract_v13.sh tools/apply_backend_resilience_bundle_v1.sh || true
git add backend/__init__.py backend/routes.py 2>/dev/null || true

if git diff --cached --quiet; then
  echo "ℹ️  Nada para commitear"
else
  git commit -m "$MSG"
fi

echo "== prepush gate =="; echo "✓ listo"
git push -u origin main

echo "== HEADs =="; echo "Local : $(git rev-parse HEAD)"; (git rev-parse @{u} >/dev/null 2>&1 && echo "Remote: $(git rev-parse @{u})") || true
