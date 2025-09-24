#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: backend/frontend patches (export WSGI + views span + tests v12)}"

git add -A
# Gate mínimo: sintaxis bash en scripts
bash -n tools/repair_shim_export_v2.sh
bash -n tools/patch_frontend_views_span.sh
bash -n tools/test_exec_integral_v12.sh

# Gate Py (por si tocaste el shim)
python - <<'PY'
import py_compile
try:
    py_compile.compile("contract_shim.py", dfile="contract_shim.py", doraise=True)
    print("✓ py_compile contract_shim.py OK")
except Exception as e:
    print("❌ py_compile contract_shim.py:", e)
    raise
PY

git commit -m "$MSG" || echo "ℹ️  Nada que commitear"
git push -u origin main
echo "✔ Push realizado (o no había cambios)."
