#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: backend rewrite __init__ (indent fix + pooling + pre_ping)}"

bash -n tools/rewrite_backend_init_clean_v2.sh
git add -f tools/rewrite_backend_init_clean_v2.sh backend/__init__.py
if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi
echo "== prepush gate =="; echo "✓ listo"
git push -u origin main
echo "== HEADs =="; echo "Local : $(git rev-parse HEAD)"; echo "Remote: $(git rev-parse @{u})"
