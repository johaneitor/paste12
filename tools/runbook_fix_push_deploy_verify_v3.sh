#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR] }"
OUTDIR="${2:-/sdcard/Download}"

echo "== RESET WSGI (seguro) =="
tools/reset_wsgi_min_safe_v2.sh

echo "== PARCHE BACKEND (métodos/POST/REST/limites) =="
tools/patch_backend_min_fixes_v1.sh

echo "== COMMIT & PUSH =="
python -m py_compile wsgi.py wsgiapp/__init__.py && echo "py_compile OK"
git add -A
git commit -m "p12: wsgi seguro + POST/OPTIONS /api/notes + REST 404 + report>=3 + TTL(72h)/CAP(200) + limiter" || true
git push -u origin main

echo "== REDEPLOY =="
tools/deploy_via_hook_or_api_v2.sh || true
tools/deploy_watch_until_v7.sh "$BASE" 900

echo "== AUDITORÍA PACK (<=10 archivos) =="
tools/p12_pack10_now_v1.sh "$BASE" "$OUTDIR" 2>/dev/null || true

echo "== VERIFICADOR INTEGRAL =="
tools/verify_all_behaviors_v6.sh "$BASE" "$OUTDIR" || true

echo "Listo. Revisá artefactos en $OUTDIR"
