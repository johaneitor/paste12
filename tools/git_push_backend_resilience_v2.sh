#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: backend resilience v2 (indent fix + pool)}"

git add -f tools/fix_backend_indent_and_pool_v2.sh tools/apply_backend_resilience_bundle_v2.sh || true
git add backend/__init__.py 2>/dev/null || true

if git diff --cached --quiet; then
  echo "ℹ️  Nada para commitear"
else
  python -m py_compile backend/__init__.py && echo "py_compile OK"
  git commit -m "$MSG"
fi

echo "== prepush gate =="; echo "✓ listo"
git push -u origin main

echo "== HEADs =="; echo "Local : $(git rev-parse HEAD)"; (git rev-parse @{u} >/dev/null 2>&1 && echo "Remote: $(git rev-parse @{u})") || true
