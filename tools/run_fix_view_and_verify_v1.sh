#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR] [apply-notes-post=yes|no]}"
OUTDIR="${2:-/sdcard/Download}"
FIX_NOTES_POST="${3:-yes}"

echo "== PATCH WSGI (GET /api/view → 404) =="
tools/patch_wsgi_fix_view_get_404_v1.sh

if [[ "$FIX_NOTES_POST" == "yes" ]]; then
  echo "== (Opcional) PATCH BE /api/notes methods =="
  tools/patch_be_enable_notes_post_v1.sh || true
fi

echo "== COMMIT & PUSH =="
python -m py_compile wsgiapp/__init__.py 2>/dev/null && echo "py_compile OK" || true
git add -A
git commit -m "p12: WSGI middleware GET /api/view -> 404 JSON (+/api/notes methods if needed)" || true
git push -u origin main

echo "== REDEPLOY =="
if [[ -n "${RENDER_DEPLOY_HOOK:-}" || ( -n "${RENDER_API_KEY:-}" && -n "${RENDER_SERVICE_ID:-}" ) ]]; then
  tools/deploy_via_hook_or_api_v2.sh || true
  tools/deploy_watch_until_v7.sh "$BASE" 900 || true
else
  echo "WARN: Sin HOOK/API en env; hacé redeploy manual y re-ejecutá verificación."
fi

echo "== QUICK SMOKE & VERIFY =="
tools/quick_smoke_now_v1.sh "$BASE" "$OUTDIR" 2>/dev/null || true
# Si tenés el verificador integral:
if [[ -x tools/verify_all_behaviors_v4.sh ]]; then
  tools/verify_all_behaviors_v4.sh "$BASE" "$OUTDIR" || true
fi

echo "Listo. Revisá artefactos en $OUTDIR (quick-smoke*, verify*, runtime-*)."
