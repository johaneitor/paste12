#!/usr/bin/env bash
set -euo pipefail
TS="$(date -u +%Y%m%d-%H%M%SZ)"
[[ -f wsgi.py ]] && cp -f wsgi.py "wsgi.${TS}.bak" && echo "[wsgi-fix] Backup: wsgi.${TS}.bak"

cat > wsgi.py <<'PY'
# wsgi.py — punto de entrada para Gunicorn: wsgi:application
from backend import create_app  # type: ignore
application = create_app()
PY

python -m py_compile wsgi.py && echo "[wsgi-fix] py_compile OK"
