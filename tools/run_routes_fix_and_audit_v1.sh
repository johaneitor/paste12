#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"

tools/patch_backend_routes_methods_v1.sh
# (opcional) robustecer pool:
tools/patch_pool_guard_safe_v1.sh || true

echo "== Ejecutando contrato de publicación =="
tools/test_publish_contract_v1.sh "$BASE" "$OUT"
echo "== Listo =="
