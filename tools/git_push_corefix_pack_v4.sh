#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: corefix — smoke+audit (max6) + frontend reconcile + stage tools}"

# Gate bash
for f in tools/run_smoke_now_v3.sh tools/unified_audit_max6_v2.sh tools/frontend_reconcile_v3.sh; do
  bash -n "$f"
done

# Gate py_compile (si existen)
pyok=1
for py in contract_shim.py wsgi.py backend/__init__.py backend/routes.py; do
  [[ -f "$py" ]] && python -m py_compile "$py" || true
done

# Stage (forzado por .gitignore)
git add -f tools/run_smoke_now_v3.sh tools/unified_audit_max6_v2.sh tools/frontend_reconcile_v3.sh 2>/dev/null || true
git add frontend/index.html 2>/dev/null || true

# Commit si hay cambios
if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi

echo "== push =="
git push -u origin main

echo "== HEADs =="
echo "Local : $(git rev-parse HEAD)"
UP="$(git rev-parse @{u} 2>/dev/null || true)"
[[ -n "$UP" ]] && echo "Remote: $UP" || echo "Remote: (upstream recién creado)"
