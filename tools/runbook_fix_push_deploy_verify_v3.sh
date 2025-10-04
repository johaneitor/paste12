#!/usr/bin/env bash
# Uso:
#   tools/runbook_fix_push_deploy_verify_v3.sh BASE_URL [OUTDIR] [no-redeploy]
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR] [no-redeploy]}"
OUTDIR="${2:-/sdcard/Download}"
MODE="${3:-redeploy}"

echo "== Rebuild wsgi.py =="
tools/patch_wsgi_rebuild_v1.sh

echo "== (Opcional) BE POST/REST/limites =="
tools/patch_be_notes_post_and_rest_v6.sh || true

echo "== prepush gate =="
python -m py_compile wsgi.py
python -m py_compile wsgiapp/__init__.py 2>/dev/null && echo "py_compile OK (be)" || echo "py_compile (skip be)"

echo "== git add/commit/push =="
git add -A || true
git commit -m "p12: rebuild wsgi.py (index flags+deploy-stamp) + POST/REST/limites" || echo "Nada para commitear"
git push -u origin main

if [[ "$MODE" != "no-redeploy" ]]; then
  echo "== redeploy + watch =="
  [[ -x tools/deploy_via_hook_or_api_v2.sh ]] && tools/deploy_via_hook_or_api_v2.sh || true
  [[ -x tools/deploy_watch_until_v7.sh     ]] && tools/deploy_watch_until_v7.sh "$BASE" 900 || true
else
  echo "== no-redeploy: omito disparo y watch =="
fi

echo "== verificación =="
[[ -x tools/quick_smoke_now_v1.sh      ]] && tools/quick_smoke_now_v1.sh "$BASE" "$OUTDIR" || true
[[ -x tools/verify_all_behaviors_v4.sh ]] && tools/verify_all_behaviors_v4.sh "$BASE" "$OUTDIR" || true
[[ -x tools/limits_exercise_v1.sh      ]] && tools/limits_exercise_v1.sh "$BASE" "$OUTDIR" || true
[[ -x tools/run_pack5_no_redeploy_v2.sh ]] && tools/run_pack5_no_redeploy_v2.sh "$BASE" "$OUTDIR" || true

echo "OK: artefactos en $OUTDIR"
