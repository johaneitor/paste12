#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUTDIR="${2:-/sdcard/Download}"

tools/patch_routes_bp_v2.sh
tools/reset_backend_factory_v7.sh

# Sanity local
python - <<'PY'
import py_compile
for f in ("backend/__init__.py", "backend/routes.py"):
    py_compile.compile(f, doraise=True)
print("py_compile OK")
PY

# Auditoría
tools/unified_smoke_and_audit_v10.sh "$BASE" "$OUTDIR"
echo "Hecho. Si todo OK, haz deploy y re-ejecuta el smoke."
