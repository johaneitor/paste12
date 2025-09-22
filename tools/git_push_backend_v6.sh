#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: backend v6 estable (health JSON, CORS 204, Link, FORM→JSON)}"

git add contract_shim.py wsgi.py wsgiapp/__init__.py || true
if git diff --cached --quiet; then
  echo "ℹ️  Nada que commitear"
else
  python - <<'PY'
import py_compile
py_compile.compile('contract_shim.py', doraise=True)
py_compile.compile('wsgi.py', doraise=True)
print("✓ py_compile contract_shim.py / wsgi.py")
PY
  git commit -m "$MSG"
fi

echo "== prepush gate =="
python - <<'PY'
import py_compile
py_compile.compile('wsgiapp/__init__.py', doraise=True)
print("✓ py_compile __init__.py OK")
PY

git push origin main
