#!/usr/bin/env bash
set -euo pipefail
TS="$(date -u +%Y%m%d-%H%M%SZ)"
[[ -f wsgi.py ]] && cp -f wsgi.py "wsgi.$TS.bak" || true

python - <<'PY'
import io, sys, textwrap

p="wsgi.py"
try:
    s = io.open(p, "r", encoding="utf-8").read()
except FileNotFoundError:
    s = ""

code = textwrap.dedent("""\
    from __future__ import annotations
    from flask import Flask

    # 1) Cargar app desde la factory principal si existe; si falla, intentar fallback conocido.
    try:
        from backend import create_app  # type: ignore
        app = create_app()
    except Exception:
        try:
            from backend.factory_stable import create_app as _cf  # type: ignore
            app = _cf()
        except Exception:
            app = Flask(__name__)

    # 2) Registrar blueprint de frontend si está disponible (idempotente)
    try:
        from backend.front_serve import front_bp  # type: ignore
        # Flask evita duplicados internamente; si ya está, no rompe.
        app.register_blueprint(front_bp)
    except Exception:
        pass

    # 3) Export requerido por Gunicorn
    application = app
""")

# Si ya exporta application y ya intenta registrar front_bp, no tocar:
if ("application =" in s) and ("front_bp" in s):
    print("[wsgi] ya tenía front_bp/application; no se modifica")
else:
    io.open(p, "w", encoding="utf-8").write(code)
    print("[wsgi] parchado con registro de front_bp + application")
PY

python -m py_compile wsgi.py
echo "[wsgi] py_compile OK"
