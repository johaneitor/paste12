#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: backend v13 (CORS 204 + Link + FORM→JSON shim)}"

# Pre-push sanity
python - <<'PY'
import py_compile
py_compile.compile("contract_shim.py", doraise=True)
PY
echo "✓ py_compile contract_shim.py"
bash -n tools/fix_backend_contract_v13.sh
bash -n tools/test_exec_backend_v13.sh
bash -n tools/deep_audit_to_sdcard_v6.sh
echo "✓ bash -n OK"

# Stage (forzar si .gitignore oculta tools/*)
git add -f contract_shim.py wsgi.py \
  tools/fix_backend_contract_v13.sh \
  tools/test_exec_backend_v13.sh \
  tools/deep_audit_to_sdcard_v6.sh

git commit -m "$MSG" || echo "ℹ️  Nada que commitear"
echo "== prepush gate =="
python - <<'PY'
import py_compile
py_compile.compile("contract_shim.py", doraise=True)
PY
echo "✓ py_compile OK"

git push origin main
echo "== Post-push =="
echo "Local : $(git rev-parse HEAD)"
echo "Remote: $(git ls-remote --heads origin main | awk '{print $1}')"
