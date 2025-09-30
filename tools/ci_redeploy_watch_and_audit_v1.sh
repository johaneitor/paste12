#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR] }"
OUTDIR="${2:-/sdcard/Download}"

# 1) Trigger vía push vacío (dispara el workflow on: push)
git commit --allow-empty -m "ci: trigger render redeploy"
git push

# 2) Watch hasta que el index remoto tenga tu HEAD (fallback a meta si no hay /api/deploy-stamp)
tools/deploy_watch_until_v7.sh "$BASE" 900

# 3) Auditorías a /sdcard/Download
tools/audit_remote_deep_v4.sh "$BASE" "$OUTDIR" >/dev/null || true
tools/live_vs_local_v1.sh     "$BASE" "$OUTDIR" >/dev/null || true
tools/audit_full_stack_v3.sh  "$BASE" "$OUTDIR" >/dev/null || true

echo "Listo. Revisá en $OUTDIR:"
echo "  - paste12-remote-deep-*.txt"
echo "  - live-vs-local-*-summary.txt"
echo "  - runtime-*.txt"
