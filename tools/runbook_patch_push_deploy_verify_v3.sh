#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR] }"
OUTDIR="${2:-/sdcard/Download}"

echo "== PATCH =="
tools/patch_reports_views_terms_antiabuse_v1.sh

echo "== COMMIT & PUSH =="
python -m py_compile wsgiapp/__init__.py
git add wsgiapp/__init__.py wsgiapp/p12_patch.py tools/patch_reports_views_terms_antiabuse_v1.sh
git commit -m "p12: terms/privacy fallback; view++ ; report threshold 3 unique; simple rate-limit; clamp limit" || true
git push -u origin main

echo "== REDEPLOY =="
tools/deploy_via_hook_or_api_v2.sh || true
tools/deploy_watch_until_v7.sh "$BASE" 900

echo "== VERIFY (pack corto) =="
# Usa tu verificador v6 y guarda 3-5 archivos máx
tools/verify_all_behaviors_v6.sh "$BASE" "$OUTDIR" || true

echo "Listo. Revisá en $OUTDIR (summary / positivos / negativos / limits)."
