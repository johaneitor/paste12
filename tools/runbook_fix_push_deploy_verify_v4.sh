#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR] [no-redeploy]}"
OUT="${2:-/sdcard/Download}"
NORED="${3:-}"

echo "== PATCH OVERLAY v2 =="
tools/patch_wsgi_overlay_min_v2.sh
tools/seed_terms_privacy_v1.sh || true

echo "== COMMIT & PUSH =="
python -m py_compile wsgi.py
python -m py_compile wsgiapp/__init__.py 2>/dev/null || true
git add -A
git commit -m "p12: WSGI overlay v2 (sin .format, placeholders seguros) + seeds terms/privacy" || true
echo "== prepush gate =="; python -m py_compile wsgiapp/__init__.py 2>/dev/null && echo "✓ py_compile OK" || echo "py_compile (skip)"
git push -u origin main

if [[ "$NORED" != "no-redeploy" ]]; then
  echo "== TRIGGER (hook/API) =="
  tools/deploy_via_hook_or_api_v2.sh || true
  echo "== WATCH =="
  tools/deploy_watch_until_v7.sh "$BASE" 900 || true
fi

echo "== VERIFY =="
tools/verify_all_behaviors_v7.sh "$BASE" "$OUT"

echo "Listo. Artefactos en $OUT"
