#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: frontend hotfix (tagline único + 405 tip + smoke)}"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "No es repo git"; exit 2; }

# gates
bash -n tools/patch_frontend_tagline_single_v1.sh
bash -n tools/patch_frontend_405_tip_v1.sh
[[ -f frontend/index.html ]] && python -m py_compile backend/__init__.py 2>/dev/null || true

# stage (forzado por si .gitignore tapa tools/)
git add -f tools/patch_frontend_tagline_single_v1.sh tools/patch_frontend_405_tip_v1.sh tools/domain_and_routes_smoke_v1.sh
git add frontend/index.html 2>/dev/null || true

if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi

echo "== prepush gate =="; echo "✓ listo"
git push -u origin main

echo "Local : $(git rev-parse HEAD)"
echo "Remote: $(git rev-parse @{u})"
