#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR] }"
OUT="${2:-/sdcard/Download}"

echo "== PATCH =="
tools/patch_wsgi_root_index_v4.sh

echo "== COMMIT & PUSH =="
python -m py_compile wsgiapp/__init__.py && echo "py_compile OK"
git add -A
git commit -m "WSGI: servir '/' + flags (p12-commit/safe-shim/single) + deploy-stamp + fallbacks [p12]" || true
git push -u origin main

echo "== REDEPLOY & WATCH =="
tools/deploy_via_hook_or_api_v2.sh
tools/deploy_watch_until_v7.sh "$BASE" 900

echo "== VERIFY =="
tools/verify_all_behaviors_v6.sh "$BASE" "$OUT" || true

echo "Listo. Último summary en: $(ls -1t "$OUT"/verify-*-summary.txt | head -1)"
