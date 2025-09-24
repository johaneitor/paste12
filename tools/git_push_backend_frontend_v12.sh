#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: backend/frontend v12 (shim + cors/link/form + views span)}"

python -m py_compile contract_shim.py wsgi.py || { echo "py_compile FAIL"; exit 1; }
[ -f frontend/index.html ] && grep -q 'class="views"' frontend/index.html || true

git add contract_shim.py wsgi.py frontend/index.html tools/apply_backend_contract_v12.sh tools/patch_frontend_views_span_v2.sh tools/test_exec_backend_v12.sh tools/deep_audit_to_sdcard_v6.sh
git commit -m "$MSG" || echo "ℹ️  Nada que commitear"
# prepush sanity
python -m py_compile contract_shim.py wsgi.py
git push origin main
