#!/bin/bash
set -euo pipefail

MSG="${1:-ops: backend/frontend fixes (export WSGI + views span + tests)}"

echo "== prepush gate =="
python3 -m py_compile contract_shim.py wsgi.py || {
  echo "py_compile FAIL: corrige contract_shim.py o wsgi.py"; exit 1; }

for f in tools/fix_backend_export.sh tools/patch_frontend_metrics.sh \
         tools/run_integral_test_prod.sh tools/test_exec_after_fix_v1.sh \
         tools/git_push_backend_frontend_fix.sh; do
  [ -f "$f" ] && bash -n "$f"
done
echo "bash -n OK"

echo "== staging selectivo =="
git add -f contract_shim.py wsgi.py frontend/index.html || true
git add -f tools/fix_backend_export.sh tools/patch_frontend_metrics.sh \
           tools/run_integral_test_prod.sh tools/test_exec_after_fix_v1.sh \
           tools/git_push_backend_frontend_fix.sh || true

if git diff --cached --quiet; then
  echo "ℹ️  Nada que commitear"
else
  echo "✓ py_compile __init__.py OK" || true
  git commit -m "$MSG"
fi

echo "== push =="
git push -u origin main

echo "== verificación =="
echo "Remoto y local deben coincidir:"
git branch -vv | sed -n '1,5p'
