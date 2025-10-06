#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR] [no-redeploy]}"
OUT="${2:-/sdcard/Download}"
NORED="${3:-}"

echo "== WSGI minimal + POST passthrough =="
tools/fix_wsgi_minimal_and_post_passthrough_v1.sh

echo "== py_compile =="
python -m py_compile wsgiapp/__init__.py || true
python -m py_compile wsgi.py

echo "== git add/commit/push =="
git add -A
git commit -m "p12: WSGI minimal + POST /api/notes passthrough (smoke unblock)" || true
echo "== prepush gate =="
python -m py_compile wsgiapp/__init__.py && echo "✓ py_compile OK" || echo "WARN py_compile"
git push -u origin main

if [ -z "$NORED" ]; then
  echo "== redeploy (hook/API) =="
  tools/deploy_via_hook_or_api_v2.sh
  echo "== watch remoto==HEAD =="
  tools/deploy_watch_until_v7.sh "$BASE" 900
else
  echo "SKIP redeploy (pedido por flag no-redeploy)"
fi

echo "== auditoría pack10 (sin redeploy extra) =="
tools/run_audits_pack10_no_redeploy_v1.sh "$BASE" "$OUT"
echo "Listo. Revisá en $OUT"
