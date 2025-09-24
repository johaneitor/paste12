#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
echo "== Paso A: probe =="; tools/deploy_probe.sh "$BASE" || true
echo "== Paso B: suites =="
tools/test_suite_all.sh "$BASE"
tools/test_suite_negative_v5.sh "$BASE" || true
echo "== Paso C: auditorías a Download =="
tools/audit_backend_to_sdcard_v3.sh "$BASE" || true
tools/audit_frontend_to_sdcard_v3.sh "$BASE" || true
tools/audit_fe_be_to_sdcard_v3.sh "$BASE" || true
tools/audit_deploy_env_v3.sh "$BASE" || true
