#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR]}"
OUTDIR="${2:-/sdcard/Download}"

echo "== Push limpio (sin workflows) =="
tools/git_unblock_workflow_and_push_v1.sh

echo "== Trigger deploy (DoH) =="
tools/deploy_via_hook_or_api_v2.sh

echo "== Watch remoto==local =="
tools/deploy_watch_until_v7.sh "$BASE" 900

echo "== Auditorías =="
tools/audit_remote_deep_v4.sh "$BASE" "$OUTDIR" >/dev/null || true
tools/live_vs_local_v1.sh     "$BASE" "$OUTDIR" >/dev/null || true
tools/audit_full_stack_v3.sh  "$BASE" "$OUTDIR" >/dev/null || true

echo "Artefactos listos en $OUTDIR"
