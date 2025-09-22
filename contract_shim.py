# -*- coding: utf-8 -*-
"""
Contract shim: garantiza que exista `application` (WSGI callable) para gunicorn.
Intenta importar la app Flask desde módulos comunes y expone:
    - application  (WSGI)
    - app          (alias opcional)
Además, agrega un after_request con CORS y soporta OPTIONS 204 para /api/notes.
"""
from __future__ import annotations

import importlib
from typing import Any

_app = None

CANDIDATES = [
    # (module, attr)
    ("wsgiapp", "app"),           # paquete local común
    ("app", "app"),               # app.py -> app = Flask(...)
    ("application", "application"),
    ("main", "app"),
]

def _load_app():
    global _app
    for mod, attr in CANDIDATES:
        try:
            m = importlib.import_module(mod)
            a = getattr(m, attr, None)
            if a is not None:
                return a
        except Exception:
            continue
    # como último intento: buscar variable "application" en wsgi.py
    try:
        m = importlib.import_module("wsgi")
        a = getattr(m, "application", None) or getattr(m, "app", None)
        if a is not None:
            return a
    except Exception:
        pass
    raise RuntimeError("No se pudo localizar una app WSGI (Flask) para exponer como `application`")

_app = _load_app()

# Exponer API esperada por gunicorn
application = _app
app = _app  # alias, por compatibilidad

# ====== Endurecer CORS & OPTIONS en /api/notes ======
try:
    from flask import request, make_response
    @app.after_request
    def _p12_cors(resp):
        # CORS estándar
        resp.headers.setdefault("Access-Control-Allow-Origin", "*")
        resp.headers.setdefault("Access-Control-Allow-Methods", "GET,POST,HEAD,OPTIONS")
        resp.headers.setdefault("Access-Control-Allow-Headers", "Content-Type, Accept")
        resp.headers.setdefault("Access-Control-Max-Age", "600")
        return resp

    # Preflight manual para /api/notes
    @app.route("/api/notes", methods=["OPTIONS"])
    def _p12_options_notes():
        r = make_response("", 204)
        r.headers["Access-Control-Allow-Origin"] = "*"
        r.headers["Access-Control-Allow-Methods"] = "GET,POST,HEAD,OPTIONS"
        r.headers["Access-Control-Allow-Headers"] = "Content-Type, Accept"
        r.headers["Access-Control-Max-Age"] = "600"
        return r
except Exception:
    # si no es Flask o falla, no bloqueamos el arranque
    pass
