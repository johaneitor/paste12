#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"

tools/fix_backend_indent_and_pool_v1.sh
tools/patch_routes_retry_db_v1.sh

echo "== Revisión sintaxis =="
python -m py_compile backend/__init__.py backend/routes.py || exit 2
echo "== Listo. Sube a Render y corre tester =="
echo "Sugerido Start Command:"
echo "  gunicorn wsgi:application --chdir /opt/render/project/src -w \${WEB_CONCURRENCY:-2} -k gthread --threads \${THREADS:-4} --timeout \${TIMEOUT:-120} -b 0.0.0.0:\$PORT"

echo "== Tester (opcional, contra prod) =="
tools/test_backend_contract_v13.sh "$BASE" || true
