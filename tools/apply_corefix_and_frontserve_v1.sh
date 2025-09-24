#!/usr/bin/env bash
set -euo pipefail

bash tools/fix_backend_init_factory_v3.sh
bash tools/write_front_serve_blueprint_v2.sh
bash tools/fix_wsgi_export_v4.sh

echo "== Compilando/verificando =="
python - <<'PY'
import py_compile
for f in ["backend/__init__.py", "backend/front_serve.py", "wsgi.py", "contract_shim.py"]:
    try:
        py_compile.compile(f, doraise=True)
        print(f"✓ py_compile {f} OK")
    except Exception as e:
        print(f"✗ py_compile {f} FAIL: {e}")
        raise
PY

echo "== Sugerido =="
echo "1) git push con tools/git_push_corefix_pack_v3.sh"
echo "2) Deploy en Render (Clear build cache + Deploy)"
echo "   Start Command:"
echo "   gunicorn wsgi:application --chdir /opt/render/project/src -w \${WEB_CONCURRENCY:-2} -k gthread --threads \${THREADS:-4} --timeout \${TIMEOUT:-120} -b 0.0.0.0:\$PORT"
echo "3) Smoke: tools/smoke_postfix_v2.sh \"https://paste12-rmsk.onrender.com\" \"/sdcard/Download\""
