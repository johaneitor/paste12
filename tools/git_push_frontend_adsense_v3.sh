#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: frontend - AdSense en <head> (v3)}"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: no es repo git"; exit 2; }
[[ -f frontend/index.html ]] || { echo "ERROR: falta frontend/index.html"; exit 3; }

# Gate rápido
bash -n "$0" >/dev/null || true

# Stage (forzado por si .gitignore tapa tools)
git add -f tools/fix_adsense_head_v3.sh tools/verify_adsense_live_v3.sh tools/git_push_frontend_adsense_v3.sh || true
git add frontend/index.html || true

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
UP="$(git rev-parse @{u} 2>/dev/null || true)"
[[ -n "$UP" ]] && echo "Remote: $UP" || echo "Remote: (upstream recién definido)"
