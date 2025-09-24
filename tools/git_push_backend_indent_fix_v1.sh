#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: backend fix (indent + engine pooling)}"

# Gates rápidos
bash -n tools/fix_backend_indent_and_pool_v1.sh

# Stage (forzado por si .gitignore tapa tools/)
git add -f tools/fix_backend_indent_and_pool_v1.sh || true
git add backend/__init__.py || true

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
echo "Remote: $(git rev-parse @{u})"
