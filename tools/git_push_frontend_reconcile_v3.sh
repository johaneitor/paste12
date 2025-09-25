#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: frontend reconcile v4 (adsense+metrics+dedupe+footer) + auditoría v4}"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: no es repo git"; exit 2; }

# Gate rápido bash
for f in tools/frontend_reconcile_v4.sh tools/audit_frontend_extensive_v4.sh tools/run_reconcile_and_audit_v3.sh; do
  bash -n "$f"
done

# Stage (forzado por .gitignore)
git add -f tools/frontend_reconcile_v4.sh tools/audit_frontend_extensive_v4.sh tools/run_reconcile_and_audit_v3.sh 2>/dev/null || true
# HTML si cambió
git add frontend/index.html 2>/dev/null || true

if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi

echo "== prepush =="
echo "✓ listo"
git push -u origin main

echo "Local : $(git rev-parse HEAD)"
echo "Remote: $(git rev-parse @{u})"
