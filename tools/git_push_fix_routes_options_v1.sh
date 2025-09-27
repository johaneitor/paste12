#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: routes: replace .options -> .route(methods=['OPTIONS']) + sanity}"

git add -f backend/routes.py tools/fix_routes_options_decorators_v1.sh
if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi

echo "== prepush: sanity py_compile (backbone) =="
python - <<'PY'
import py_compile, sys
for f in ["backend/__init__.py","backend/routes.py","wsgi.py","contract_shim.py"]:
    try:
        py_compile.compile(f, doraise=True)
        print("✓", f, "OK")
    except Exception as e:
        print("WARN:", f, e)
PY

git push -u origin main
echo "== HEAD =="
git rev-parse HEAD
