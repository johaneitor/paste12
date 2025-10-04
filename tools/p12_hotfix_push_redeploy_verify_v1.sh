#!/usr/bin/env bash
# Uso:
#   tools/p12_hotfix_push_redeploy_verify_v1.sh BASE_URL [OUTDIR] [no-redeploy]
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR] [no-redeploy]}"
OUTDIR="${2:-/sdcard/Download}"
MODE="${3:-redeploy}"

echo "== WSGI hotfix =="
tools/hotfix_wsgi_rebuild_v1.sh

echo "== BE POST & REST/404 & límites x2 =="
tools/patch_be_notes_post_and_rest_v4.sh

echo "== compile (estricto) =="
python -m py_compile wsgiapp/__init__.py && echo "py_compile OK"

echo "== git add/commit/push =="
git add -A || true
git commit -m "p12: WSGI canónico + POST /api/notes + REST 404 like/report + límites x2" || echo "Nada para commitear"
if [[ -x tools/git_unblock_workflow_and_push_v1.sh ]]; then
  tools/git_unblock_workflow_and_push_v1.sh
else
  git push -u origin main
fi

if [[ "$MODE" != "no-redeploy" ]]; then
  echo "== redeploy + watch =="
  if [[ -x tools/deploy_via_hook_or_api_v2.sh ]]; then
    tools/deploy_via_hook_or_api_v2.sh
  fi
  if [[ -x tools/deploy_watch_until_v7.sh ]]; then
    tools/deploy_watch_until_v7.sh "$BASE" 900
  fi
else
  echo "== no-redeploy activado, salto deploy/watch =="
fi

echo "== verificaciones =="
[[ -x tools/quick_smoke_now_v1.sh ]] && tools/quick_smoke_now_v1.sh "$BASE" "$OUTDIR" || true
[[ -x tools/verify_all_behaviors_v4.sh ]] && tools/verify_all_behaviors_v4.sh "$BASE" "$OUTDIR" || true
[[ -x tools/run_pack5_no_redeploy_v2.sh ]] && tools/run_pack5_no_redeploy_v2.sh "$BASE" "$OUTDIR" || true

echo "Artefactos en $OUTDIR"
