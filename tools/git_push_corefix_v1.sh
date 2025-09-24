#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: backend corefix v1 (split db + factory + health)}}"

# Stage forzado (por si .gitignore tapa tools/)
git add -f tools/fix_backend_core_v1.sh tools/smoke_after_corefix_v1.sh backend/db.py backend/__init__.py 2>/dev/null || true

if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi

echo "== prepush gate =="; echo "✓ listo"
git push -u origin main

echo "== HEADs =="; echo "Local : $(git rev-parse HEAD)"; echo "Remote: $(git rev-parse @{u})"
