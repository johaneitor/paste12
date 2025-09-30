#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR] }"
OUTDIR="${2:-/sdcard/Download}"
# Derivar SERVICE_ID desde el HOOK o variable
SERVICE_ID="${RENDER_SERVICE_ID:-}"
if [[ -z "$SERVICE_ID" && -n "${RENDER_DEPLOY_HOOK:-}" ]]; then
  SERVICE_ID="$(sed -n 's#.*deploy/\(srv-[a-z0-9]\+\)?.*#\1#p' <<<"$RENDER_DEPLOY_HOOK")"
fi
[[ -n "$SERVICE_ID" ]] || { echo "ERROR: falta SERVICE_ID (seteá RENDER_SERVICE_ID o RENDER_DEPLOY_HOOK)"; exit 2; }

echo "== show core =="
tools/render_service_show_core_v1.sh "$SERVICE_ID" || true

echo "== ensure autodeploy on main =="
tools/render_service_autodeploy_on_v1.sh "$SERVICE_ID" || true

echo "== patch WSGI =="
tools/patch_wsgi_index_middleware_v2.sh
python -m py_compile wsgiapp/__init__.py || true

echo "== commit & push =="
git add -A
git commit -m "p12: fix WSGI index override + ensure flags + 404 unify" || true
git push -u origin main

echo "== trigger deploy (API) =="
curl -fsS -X POST \
  -H "Authorization: Bearer ${RENDER_API_KEY:?Falta RENDER_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{}' "https://api.render.com/v1/services/${SERVICE_ID}/deploys" >/dev/null && echo "OK: deploy creado"

echo "== purge web cache =="
curl -fsS -X POST -H "Authorization: Bearer ${RENDER_API_KEY}" \
  "https://api.render.com/v1/services/${SERVICE_ID}/purge-cache" >/dev/null && echo "OK: cache purged"

echo "== watch remoto==HEAD =="
tools/deploy_watch_until_v7.sh "$BASE" 900 || true

echo "== auditorías =="
tools/audit_remote_deep_v4.sh "$BASE" "$OUTDIR" >/dev/null || true
tools/live_vs_local_v1.sh     "$BASE" "$OUTDIR" >/dev/null || true
tools/audit_full_stack_v3.sh  "$BASE" "$OUTDIR" >/dev/null || true

echo "Artefactos en $OUTDIR"
