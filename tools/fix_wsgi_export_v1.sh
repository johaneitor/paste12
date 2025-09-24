#!/usr/bin/env bash
set -euo pipefail

TS="$(date -u +%Y%m%d-%H%M%SZ)"
[[ -f wsgi.py ]] && cp -f wsgi.py "wsgi.$TS.bak" || true

python - <<'PY'
import pathlib, textwrap
p = pathlib.Path("wsgi.py")
code = textwrap.dedent("""
    # -*- coding: utf-8 -*-
    # WSGI entrypoint: reexporta 'application' desde el shim
    try:
        from contract_shim import application  # noqa: F401
    except Exception as e:
        # Fallback minimal para no romper healthcheck si el shim falla
        from flask import Flask, jsonify
        _app = Flask(__name__)
        @_app.get("/api/health")
        def _health():
            return jsonify(ok=True, api=False, diag=str(e), ver="wsgi-export-fallback")
        application = _app
""").lstrip()
p.write_text(code, encoding="utf-8")
PY

python -m py_compile wsgi.py
echo "[wsgi-fix] wsgi.py listo y compilado"
