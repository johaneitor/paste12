#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR]}"
OUTDIR="${2:-/sdcard/Download}"
: "${RENDER_API_KEY:?export RENDER_API_KEY=rnd_...}"

# A) Service ID correcto
eval "$(tools/render_autodetect_srv_v1.sh "$BASE")"

# B) Inspect (solo para log; no abortar por url=None)
tools/render_service_inspect_v5.sh || true

# C) Parches mínimos (idempotentes)
tools/patch_wsgi_index_middleware_v1.sh || true
tools/patch_backend_404_unify_v3.sh || true

# D) Commit/push
python -m py_compile wsgiapp/__init__.py || true
git add -A
git commit -m "fix(p12): WSGI index override + 404 unify" || true
git push -u origin main

# E) Redeploy por API + watch + auditorías
tools/redeploy_via_api_and_watch_v4.sh "$BASE" "$OUTDIR"

# F) Auditorías finales redundantes
tools/live_vs_local_v1.sh    "$BASE" "$OUTDIR" || true
tools/audit_full_stack_v3.sh "$BASE" "$OUTDIR" || true
echo "OK. Artefactos en $OUTDIR"
