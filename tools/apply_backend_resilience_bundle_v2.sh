#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"

tools/fix_backend_indent_and_pool_v2.sh

echo "== Revisión sintaxis =="
python -m py_compile backend/__init__.py || exit 2

echo "== CONSEJO Start Command =="
echo "gunicorn wsgi:application --chdir /opt/render/project/src -w ${WEB_CONCURRENCY:-2} -k gthread --threads ${THREADS:-4} --timeout ${TIMEOUT:-120} -b 0.0.0.0:$PORT"

echo "== Smoke corto (contra prod) =="
curl -fsS "$BASE/api/health" >/dev/null && echo "OK  - health" || echo "WARN- health (revisar tras deploy)"
