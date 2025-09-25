#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: frontend reconcile v2 (adsense+views+dedup+seo)}"

# gate git
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: no es repo git"; exit 2; }

# gates de sintaxis
bash -n tools/frontend_reconcile_v2.sh

# stage (forzado por .gitignore para tools/)
git add -f tools/frontend_reconcile_v2.sh || true
[[ -f tools/run_reconcile_and_audit_v3.sh ]] && git add -f tools/run_reconcile_and_audit_v3.sh || true
[[ -f tools/unified_audit_pack_v3.sh      ]] && git add -f tools/unified_audit_pack_v3.sh      || true

# agregar HTML si cambió
git add frontend/index.html 2>/dev/null || true

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
[[ -n "$UP" ]] && echo "Remote: $UP" || echo "Remote: (se definirá en el primer push)"
