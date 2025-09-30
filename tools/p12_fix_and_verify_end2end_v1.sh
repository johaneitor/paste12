#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR] }"
OUTDIR="${2:-/sdcard/Download}"
: "${RENDER_DEPLOY_HOOK:?export RENDER_DEPLOY_HOOK=...}"
: "${RENDER_API_KEY:?export RENDER_API_KEY=rnd_...}"

# 0) Sanity del HOOK vs BASE
tools/hook_matches_base_v1.sh "$BASE" | tee /dev/stderr | grep -q 'MATCH: YES' || {
  echo "ERROR: HOOK no corresponde a BASE. Actualizá RENDER_DEPLOY_HOOK y reintenta."
  exit 2
}

# 1) Parcheos mínimos idempotentes (index override + 404 unify)
tools/patch_wsgi_index_middleware_v1.sh || true
tools/patch_backend_404_unify_v3.sh || true
python -m py_compile wsgiapp/__init__.py || true
git add -A
git commit -m "p12: enforce index flags + 404 unify" || true
git push -u origin main

# 2) Dispara deploy vía hook → obtiene DEP_ID
DEP_ID="$(tools/deploy_hook_get_id_v4.sh)"
[ -n "$DEP_ID" ] || { echo "ERROR: sin DEP_ID"; exit 3; }

# 3) Mejor esfuerzo por obtener SERVICE_ID (si falla, no bloquea)
SID="$(tools/render_deploy_status_get_service_v3.sh "$DEP_ID" || true)"
[ -n "$SID" ] || SID="$(echo "$RENDER_DEPLOY_HOOK" | sed -n 's#.*deploy/\(srv-[a-z0-9]\+\)\?.*#\1#p')"

# 4) Tiro de gracia: crear otro deploy por API al mismo servicio (asegura que Render tome HEAD)
[ -n "$SID" ] && tools/redeploy_with_service_and_watch_v4.sh "$BASE" "$SID" "$OUTDIR"

# 5) Auditorías extra por claridad
tools/live_vs_local_v1.sh    "$BASE" "$OUTDIR" || true
tools/audit_full_stack_v3.sh "$BASE" "$OUTDIR" || true
echo "OK. Artefactos en $OUTDIR"
