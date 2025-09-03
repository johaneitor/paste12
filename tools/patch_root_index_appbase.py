#!/usr/bin/env python3
import pathlib, re, sys

# 1) detectar archivo fuente de la app base
candidates = [pathlib.Path("backend/__init__.py"), pathlib.Path("backend/app.py")]
P = next((p for p in candidates if p.exists()), None)
if not P:
    print("ERROR: no encontré backend/__init__.py ni backend/app.py")
    sys.exit(1)

s = P.read_text(encoding="utf-8")
changed = False

# 2) asegurar imports mínimos
def ensure(line):
    global s, changed
    if line not in s:
        # insertamos después del primer 'import' o al inicio
        m = re.search(r'^\s*import[^\n]*\n', s, flags=re.M)
        if m:
            s = s[:m.end()] + line + "\n" + s[m.end():]
        else:
            s = line + "\n" + s
        changed = True

ensure("import os")
ensure("from flask import request, make_response")

# 3) función + hook before_request (idempotente)
if "_pastel_root_installed" not in s:
    patch = r"""

# --- pastel root (idempotente): sirve backend/static/index.html en "/" ---
def _serve_pastel_root():
    try:
        here = os.path.dirname(__file__)
        p = os.path.join(here, "static", "index.html")
        with open(p, "rb") as f:
            data = f.read()
    except Exception:
        return None  # dejar que siga el ruteo normal
    resp = make_response(data, 200)
    resp.headers["Content-Type"] = "text/html; charset=utf-8"
    resp.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    resp.headers["X-Index-Source"] = "app-base"
    return resp

try:
    # 'app' debe existir en este módulo (Flask app)
    app
    if not getattr(app, "_pastel_root_installed", False):
        @app.before_request
        def _pastel_root_intercept():
            # intercepta solo GET/HEAD de "/" o "/index.html"
            m = (request.method or "GET").upper()
            if request.path in ("/", "/index.html") and m in ("GET", "HEAD"):
                resp = _serve_pastel_root()
                if resp is not None and m == "HEAD":
                    # sin cuerpo en HEAD
                    resp.set_data(b"")
                return resp  # corta el ruteo
        app._pastel_root_installed = True
except NameError:
    # si no hay 'app', no hacemos nada (ambiente no esperado)
    pass
"""
    s += patch
    changed = True

if changed:
    P.write_text(s, encoding="utf-8")
    print(f"patched: {P}")
else:
    print("sin cambios (ya estaba aplicado)")
