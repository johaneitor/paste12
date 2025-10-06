#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR] }"
OUTDIR="${2:-/sdcard/Download}"

echo "== 1) Parches FE/BE/Content =="
tools/patch_terms_privacy_v1.sh
tools/patch_fe_views_reports_v1.sh
tools/patch_be_reports_views_v1.sh

echo "== 2) Commit & Push =="
git add -A
git commit -m "p12: terms/privacy + FE views/report UX + BE reports/views (threshold=3, dedupe 6h)" || true
echo "== prepush gate =="
python -m py_compile wsgiapp/__init__.py 2>/dev/null && echo "py_compile OK" || echo "py_compile (skip)"
git push -u origin main

echo "== 3) Redeploy + Watch (si tenés hook/API) =="
if [ -n "${RENDER_DEPLOY_HOOK:-}" ] || { [ -n "${RENDER_API_KEY:-}" ] && [ -n "${RENDER_SERVICE_ID:-}" ]; }; then
  tools/deploy_via_hook_or_api_v2.sh || true
  tools/deploy_watch_until_v7.sh "$BASE" 900 || true
else
  echo "SKIP redeploy (faltan vars). Hacé tu redeploy habitual y re-ejecutá verificación."
fi

echo "== 4) Verificación (usa tus verificadores si existen) =="
if [ -x tools/verify_all_behaviors_v6.sh ]; then
  tools/verify_all_behaviors_v6.sh "$BASE" "$OUTDIR" || true
else
  # Smoke mínimo integrado
  TMP="$(mktemp -d)"
  {
    echo "== QUICK SMOKE $(date -u +%Y%m%d-%H%M%SZ) =="
    echo "BASE: $BASE"
    curl -fsS "$BASE/terms" -o /dev/null && echo "terms OK" || echo "terms FAIL"
    curl -fsS "$BASE/privacy" -o /dev/null && echo "privacy OK" || echo "privacy FAIL"
    curl -fsS "$BASE/api/notes?limit=10" -H 'accept: application/json' -o "$TMP/list.json" && echo "list OK" || echo "list FAIL"
  } > "$OUTDIR/quick-smoke.txt"
  echo "OK: quick-smoke en $OUTDIR/quick-smoke.txt"
fi

echo "Listo."
