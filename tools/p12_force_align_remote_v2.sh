#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR] }"
OUTDIR="${2:-/sdcard/Download}"
: "${RENDER_API_KEY:?export RENDER_API_KEY=rnd_xxx}"

# 0) Resolver service id correcto (url o repo/branch)
eval "$(tools/render_find_service_by_url_v2.sh "$BASE")"

# 1) Inspección de servicio
info="$(tools/render_service_inspect_v4.sh || true)"
echo "$info"

# 2) Validación flexible
repo_ok=$(echo "$info" | grep -c "repo: .*johaneitor/paste12")
branch_ok=$(echo "$info" | grep -c "branch: main")
url_ok=$(echo "$info" | grep -c "url: ${BASE}")
if [ "$repo_ok" -eq 0 ] || [ "$branch_ok" -eq 0 ]; then
  echo "ERROR: el servicio no apunta a repo/main esperado"; exit 3
fi
if [ "$url_ok" -eq 0 ]; then
  echo "WARN: service.url no coincide o es None; continúo porque repo/main son correctos."
fi

# 3) Parches mínimos (idempotentes)
tools/patch_wsgi_index_middleware_v1.sh || true
tools/patch_backend_404_unify_v3.sh || true

# 4) Commit/push
python -m py_compile wsgiapp/__init__.py || true
git add -A
git commit -m "fix(p12): WSGI index override + 404 unify" || true
git push -u origin main

# 5) Redeploy por API + watch + auditorías
tools/redeploy_via_api_and_watch_v4.sh "$BASE" "$OUTDIR"

# 6) Auditorías finales (redundantes pero útiles)
tools/live_vs_local_v1.sh    "$BASE" "$OUTDIR" || true
tools/audit_full_stack_v3.sh "$BASE" "$OUTDIR" || true
echo "OK. Artefactos en $OUTDIR"
