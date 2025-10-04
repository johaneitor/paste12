#!/usr/bin/env bash
# Uso:
#   tools/runbook_fix_push_deploy_verify_v2.sh BASE_URL [OUTDIR] [no-redeploy]
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR] [no-redeploy]}"
OUTDIR="${2:-/sdcard/Download}"
MODE="${3:-redeploy}"

echo "== RESTORE backend (solo __init__.py) =="
tools/restore_backend_from_origin_main_v1.sh

echo "== PATCH backend (POST/REST/límites) =="
tools/patch_be_notes_post_and_rest_v6.sh

echo "== SANITIZE wsgi.py =="
tools/patch_wsgi_sanitize_min_v1.sh

echo "== prepush gate =="
python -m py_compile wsgiapp/__init__.py && echo "py_compile OK"

echo "== git add/commit/push =="
git add -A || true
git commit -m "p12: POST /api/notes + REST 404 + límites x2 + sanitize wsgi.py" || echo "Nada para commitear"
git push -u origin main

if [[ "$MODE" != "no-redeploy" ]]; then
  echo "== redeploy + watch =="
  if [[ -x tools/deploy_via_hook_or_api_v2.sh ]]; then tools/deploy_via_hook_or_api_v2.sh; fi
  if [[ -x tools/deploy_watch_until_v7.sh     ]]; then tools/deploy_watch_until_v7.sh "$BASE" 900; fi
else
  echo "== no-redeploy: omito disparo y watch =="
fi

echo "== verificación (smoke + verify + límites) =="
[[ -x tools/quick_smoke_now_v1.sh           ]] && tools/quick_smoke_now_v1.sh "$BASE" "$OUTDIR" || true
[[ -x tools/verify_all_behaviors_v4.sh      ]] && tools/verify_all_behaviors_v4.sh "$BASE" "$OUTDIR" || true
[[ -x tools/limits_exercise_v1.sh           ]] && tools/limits_exercise_v1.sh "$BASE" "$OUTDIR" || true
[[ -x tools/run_pack5_no_redeploy_v2.sh     ]] && tools/run_pack5_no_redeploy_v2.sh "$BASE" "$OUTDIR" || true

echo "OK: artefactos en $OUTDIR"
