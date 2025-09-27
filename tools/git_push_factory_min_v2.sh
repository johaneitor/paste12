#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: factory_min_stable (backend+front_bp+wsgi) + smokes + audits}"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: no es repo git"; exit 2; }

git add -f backend/__init__.py backend/routes.py backend/front_bp.py wsgi.py \
  tools/install_factory_min_stable_v1.sh tools/smoke_min_v1.sh tools/live_vs_local_audit_v5.sh

python - <<'PY'
import py_compile
for f in ["backend/__init__.py","backend/routes.py","backend/front_bp.py","wsgi.py"]:
    py_compile.compile(f, doraise=True)
print("py_compile OK")
PY

if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi

echo "== prepush: py_compile OK =="
git push -u origin main || { echo "⚠️  push falló (red/acceso)."; exit 0; }
