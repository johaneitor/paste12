#!/usr/bin/env bash
set -euo pipefail

BASE="${1:?Uso: $0 BASE_URL [OUTDIR] }"
OUTDIR="${2:-/sdcard/Download}"

# 0) Validaciones de entorno
: "${RENDER_API_KEY:?export RENDER_API_KEY=rnd_xxx (completa, sin truncar)}"
[[ "${RENDER_API_KEY}" == rnd_* ]] || { echo "ERROR: RENDER_API_KEY debe empezar con rnd_"; exit 2; }
(( ${#RENDER_API_KEY} >= 25 )) || { echo "ERROR: RENDER_API_KEY parece truncada (muy corta)"; exit 2; }

# 1) Resolver el Service ID correcto por URL y exportarlo
eval "$(tools/render_find_service_by_url_v1.sh "$BASE")"

# 2) Inspección (repo/branch/url) — abort si no coincide
info="$(tools/render_service_inspect_v4.sh)"
echo "$info"
echo "$info" | grep -q "url: ${BASE}"      || { echo "ERROR: el servicio no corresponde a ${BASE}"; exit 3; }
echo "$info" | grep -q "repo: johaneitor/paste12" || { echo "ERROR: repo incorrecto"; exit 3; }
echo "$info" | grep -q "branch: main"      || { echo "ERROR: branch incorrecto"; exit 3; }

# 3) Aplicar parches mínimos y publicar
#    - middleware WSGI: sirve index con p12-commit + safe-shim + data-single="1"
#    - 404 unify en like/view/report
tools/patch_wsgi_index_middleware_v1.sh || true
tools/patch_backend_404_unify_v3.sh || true
python -m py_compile wsgiapp/__init__.py || true
git add -A
git commit -m "fix(p12): WSGI index override + 404 unify" || true
git push -u origin main

# 4) Redeploy por API (sin DNS local), watch remoto==local, auditorías
tools/redeploy_via_api_and_watch_v4.sh "$BASE" "$OUTDIR"

# 5) Auditorías extra por claridad (idempotentes)
tools/live_vs_local_v1.sh "$BASE" "$OUTDIR" || true
tools/audit_full_stack_v3.sh "$BASE" "$OUTDIR" || true

echo "OK. Artefactos en $OUTDIR"
