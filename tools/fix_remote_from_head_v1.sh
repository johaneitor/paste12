#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR] }"
OUTDIR="${2:-/sdcard/Download}"

# 1) Parches BE/FE
tools/patch_backend_404_unify_v2.sh
tools/patch_backend_deploy_stamp_v1.sh
tools/patch_frontend_force_shim_single_v3.sh
tools/patch_frontend_version_assets_v1.sh || true

# 2) Push + redeploy (hook si hay, si no git bump)
git push -u origin HEAD:main
if tools/deploy_trigger_via_hook_safe.sh; then :; else tools/deploy_trigger_via_git_bump_v2.sh; fi
tools/deploy_watch_until_v6.sh "$BASE" 480

# 3) Auditorías finales (remoto puro + stack)
tools/audit_remote_deep_v4.sh "$BASE" "$OUTDIR" >/dev/null
tools/audit_full_stack_v3.sh  "$BASE" "$OUTDIR" >/dev/null

# 4) Resumen
echo "==== RESUMEN ===="
ls -1t "$OUTDIR"/paste12-remote-deep-*.txt | head -n1 | xargs -I{} sh -c 'echo "-- REMOTE DEEP --"; tail -n +1 "{}" | sed -n "1,200p"'
echo
ls -1t "$OUTDIR"/runtime-positive-*.txt | head -n1 | xargs -I{} sh -c 'echo "-- SUITE POSITIVA --"; tail -n 5 "{}"'
ls -1t "$OUTDIR"/runtime-negative-*.txt | head -n1 | xargs -I{} sh -c 'echo "-- SUITE NEGATIVA --"; cat "{}"'
