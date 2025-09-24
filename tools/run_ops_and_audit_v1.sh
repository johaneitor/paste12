#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUTDIR="${2:-/sdcard/Download}"

echo "== Aplicando parches =="
tools/patch_db_pooling_v4.sh
tools/patch_head_handler_v1.sh
tools/patch_frontend_seo_v2.sh

echo "== Compilando/verificando =="
python -m py_compile backend/__init__.py contract_shim.py || true

echo "== Auditoría unificada (super) =="
tools/unified_audit_super_v1.sh "$BASE" "$OUTDIR"

echo "== Hecho =="
echo "• Si corresponde, hacé deploy en Render (Clear build cache) y repetí la auditoría."
