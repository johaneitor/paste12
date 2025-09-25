#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: frontend hard reconcile v4 (fix SW + endpoints + dedup + adsense)}"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: no es repo git"; exit 2; }

# Gate rápido
bash -n tools/frontend_hard_reconcile_v4.sh

# Stage
git add -f tools/frontend_hard_reconcile_v4.sh frontend/index.html 2>/dev/null || true

if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi

echo "== prepush =="
echo "✓ listo"
git push -u origin main

echo "== HEADs =="
echo "Local : $(git rev-parse HEAD)"
UP="$(git rev-parse @{u} 2>/dev/null || true)"
[[ -n "$UP" ]] && echo "Remote: $UP" || echo "Remote: (upstream configurado recién)"
