#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR] [no-redeploy]}"
OUTDIR="${2:-/sdcard/Download}"
NORED="${3:-}"

echo "== 1) Sanear WSGI (idempotente) =="
tools/patch_wsgi_min_clean_v1.sh

echo "== 2) Compilar y push =="
python -m py_compile wsgiapp/__init__.py || true
git add -A
git commit -m "infra(p12): wsgi minimal, flags index & fallbacks" || true
git push -u origin main

if [[ -z "${NORED}" ]]; then
  echo "== 3) Redeploy + watch =="
  tools/deploy_via_hook_or_api_v2.sh
  tools/deploy_watch_until_v7.sh "$BASE" 900
else
  echo "== 3) SKIP redeploy por flag no-redeploy =="
fi

echo "== 4) Verificaciones sin tocar deploy =="
tools/run_audits_no_redeploy_v1.sh "$BASE" "$OUTDIR" || true
tools/smoke_verify_limits_no_redeploy_v1.sh "$BASE" "$OUTDIR" || true

echo "Listo. Mirá en: $OUTDIR"
