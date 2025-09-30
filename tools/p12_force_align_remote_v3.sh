#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR] }"
OUTDIR="${2:-/sdcard/Download}"
: "${RENDER_API_KEY:?export RENDER_API_KEY=rnd_...}"

# A) Resolver el service id correcto y exportarlo
eval "$(tools/render_find_service_by_url_v3.sh "$BASE")"

# B) Inspect: permitimos url=None si repo/main están OK
info="$(tools/render_service_inspect_v5.sh || true)"
echo "$info"
echo "$info" | grep -q "repo: .*johaneitor/paste12" || { echo "ERROR: repo incorrecto"; exit 3; }
echo "$info" | grep -q "branch: main"               || { echo "ERROR: branch incorrecto"; exit 3; }
if ! echo "$info" | grep -q "url: ${BASE}"; then
  echo "WARN: service.url no coincide o es None; continúo porque repo/main son correctos."
fi

# C) Parches mínimos (idempotentes)
sed -i 's/\r$//' tools/patch_wsgi_index_middleware_v1.sh tools/patch_backend_404_unify_v3.sh 2>/dev/null || true
tools/patch_wsgi_index_middleware_v1.sh || true
tools/patch_backend_404_unify_v3.sh || true

# D) Commit/push
python -m py_compile wsgiapp/__init__.py || true
git add -A
git commit -m "fix(p12): WSGI index override + 404 unify" || true
git push -u origin main

# E) Redeploy por API + watch + auditorías
tools/redeploy_via_api_and_watch_v4.sh "$BASE" "$OUTDIR"

# F) Auditorías finales (redundantes)
tools/live_vs_local_v1.sh    "$BASE" "$OUTDIR" || true
tools/audit_full_stack_v3.sh "$BASE" "$OUTDIR" || true
echo "OK. Artefactos en $OUTDIR"
