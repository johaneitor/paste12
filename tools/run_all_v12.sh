#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL}"

tools/apply_backend_contract_v12.sh
tools/patch_frontend_views_span_v2.sh

echo "== Probar backend =="
tools/test_exec_backend_v12.sh "$BASE"

echo "== Auditoría a /sdcard/Download =="
tools/deep_audit_to_sdcard_v6.sh "$BASE" /sdcard/Download

echo "Listo. Si todo OK:"
echo "  tools/git_push_backend_frontend_v12.sh \"ops: backend/frontend v12 estable\""
