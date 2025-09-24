# -*- coding: utf-8 -*-
"""
contract_shim: resuelve la app WSGI de forma robusta.
- Inyecta CORS si el código del backend la usa sin importarla.
- Expone `application` para gunicorn (wsgi:application).
- Responde /api/health aunque falle el import, con diagnóstico.
"""
from __future__ import annotations
import builtins, importlib, os, traceback
from typing import Any, Callable

# Asegurar CORS en globales si el backend lo usa sin import
try:
    from flask_cors import CORS  # type: ignore
    if not hasattr(builtins, "CORS"):
        builtins.CORS = CORS  # type: ignore[attr-defined]
except Exception:
    # Si no está instalada flask-cors, seguimos; /api/health igual funciona en fallback
    pass

def _make_fallback_app(diag: str) -> Any:
    from flask import Flask, jsonify, send_file, abort
    app = Flask(__name__, static_folder=None)
    @app.get("/api/health")
    def health():
        return jsonify({"ok": True, "api": False, "diag": diag, "ver":"shim-fallback-v4"})
    @app.get("/")
    def index():
        p = os.path.join(os.getcwd(), "frontend", "index.html")
        if os.path.isfile(p):
            return send_file(p)
        abort(404)
    return app

def _resolve_real_app() -> Any:
    """
    Intenta en orden:
      1) backend.app:app
      2) backend:create_app()
      3) backend.main:app
      4) backend.wsgi:app
      5) backend:app
      6) app:app
      7) run:app
    """
    tried = []
    # Helper para “import módulo:objeto”
    def try_import(modname: str, attr: str|None=None, call: bool=False):
        m = importlib.import_module(modname)
        obj = getattr(m, attr) if attr else m
        return obj() if call else obj
    try:
        return try_import("backend.app","app")
    except Exception as e:
        tried.append(f"backend.app:app -> {e.__class__.__name__}: {e}")

    try:
        create_app = try_import("backend","create_app")
        return create_app()
    except Exception as e:
        tried.append(f"backend:create_app -> {e.__class__.__name__}: {e}")

    for target in [("backend.main","app"), ("backend.wsgi","app"), ("backend","app"), ("app","app")]:
        try:
            return try_import(*target)
        except Exception as e:
            tried.append(f"{target[0]}:{target[1]} -> {e.__class__.__name__}: {e}")

    try:
        return try_import("run","app")
    except Exception as e:
        tried.append(f"run:app -> {e.__class__.__name__}: {e}")

    raise RuntimeError(" ; ".join(tried))

def _wrap_with_cors(app: Any) -> Any:
    try:
        # Si CORS quedó disponible (inyectado), úsalo. Si no, continúa sin CORS.
        cors = getattr(builtins, "CORS", None)
        if cors and not getattr(app, "_p12_cors_applied", False):
            cors(app, resources={r"/api/*": {"origins": "*"}})
            setattr(app, "_p12_cors_applied", True)
    except Exception:
        pass
    return app

def _ensure_health(app: Any) -> Any:
    try:
        # Si ya existe /api/health, no hacemos nada
        urls = {getattr(r, "rule", None) for r in getattr(app, "url_map", [])}
        if "/api/health" in urls:
            return app
    except Exception:
        pass
    try:
        from flask import jsonify
        @app.get("/api/health")
        def _p12_health():
            return jsonify({"ok": True, "api": True, "ver": "wsgi-lazy-v3"})
    except Exception:
        pass
    return app

def _build_application() -> Any:
    try:
        real_app = _resolve_real_app()
        real_app = _wrap_with_cors(real_app)
        real_app = _ensure_health(real_app)
        return real_app
    except Exception as e:
        diag = f"no pude resolver app WSGI: {e}"
        return _make_fallback_app(diag)

application = _build_application()  # WSGI callable
app = application  # alias por si acaso
