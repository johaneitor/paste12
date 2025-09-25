#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: backend api_unavailable + FE reconcile + unified audit (v2)}"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: no es repo git"; exit 2; }

# Stage
git add -f backend/__init__.py 2>/dev/null || true
git add -f tools/fix_backend_api_unavailable_v3.sh tools/frontend_reconcile_v5.sh tools/unified_audit_max6_v2.sh 2>/dev/null || true

# Commit si hay cambios
if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi

echo "== prepush =="
python3 - <<'PY'
import py_compile, sys
py_compile.compile("backend/__init__.py", doraise=True); print("✓ py_compile backend/__init__.py")
PY

git push -u origin main || {
  echo "⚠️  Push falló (¿sin conectividad o credenciales?)."
  exit 0
}

echo "== HEADs =="
echo "Local : $(git rev-parse HEAD)"
U="$(git rev-parse @{u} 2>/dev/null || true)"
[[ -n "$U" ]] && echo "Remote: $U" || echo "Remote: (upstream recién creado)"
