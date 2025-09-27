#!/usr/bin/env bash
set -euo pipefail
TS="$(date -u +%Y%m%d-%H%M%SZ)"
INI="backend/__init__.py"
[[ -f "$INI" ]] || { echo "ERROR: falta $INI"; exit 1; }
cp -f "$INI" "$INI.$TS.bak"
echo "[factory] Backup: $INI.$TS.bak"

python - <<'PY'
import os, io, re, textwrap

p = "backend/__init__.py"
s = io.open(p, "r", encoding="utf-8").read()

code = r'''
from __future__ import annotations
import os
from flask import Flask, jsonify, request
from flask_cors import CORS
try:
    from flask_sqlalchemy import SQLAlchemy
except Exception:  # fallback para py_compile en local
    SQLAlchemy = None

# SQLAlchemy global opcional (evita import circular)
db = SQLAlchemy() if SQLAlchemy else None

def _apply_cors_headers(resp):
    resp.headers["Access-Control-Allow-Origin"]  = "*"
    resp.headers["Access-Control-Allow-Methods"] = "GET, POST, HEAD, OPTIONS"
    resp.headers["Access-Control-Allow-Headers"] = "Content-Type"
    resp.headers["Access-Control-Max-Age"]       = "86400"
    return resp

def create_app():
    app = Flask(__name__)

    # ---- DB segura (Render: DATABASE_URL) ----
    uri = os.getenv("DATABASE_URL") or os.getenv("DATABASE_URI") or ""
    if uri.startswith("postgres://"):
        uri = uri.replace("postgres://", "postgresql+psycopg2://", 1)
    if uri:
        app.config["SQLALCHEMY_DATABASE_URI"] = uri
    else:
        # fallback para que el import nunca explote
        app.config["SQLALCHEMY_DATABASE_URI"] = "sqlite:////tmp/paste12.db"
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

    # ---- CORS en /api/* ----
    CORS(app, resources={r"/api/*": {"origins": "*"}}, supports_credentials=False)

    # ---- Inicializar DB si está disponible ----
    global db
    if db:
        try:
            db.init_app(app)
        except Exception as e:
            app.logger.warning("DB init warning: %r", e)

    # ---- health temprano, siempre disponible ----
    @app.get("/api/health")
    def _early_health():
        loaded = "api" in app.blueprints
        return jsonify(ok=True, api=loaded, ver="factory-v7")

    # ---- intentar registrar blueprint real ----
    api_loaded = False
    try:
        from .routes import api_bp  # debe existir si hay API real
        app.register_blueprint(api_bp)
        api_loaded = True
    except Exception as e:
        app.logger.error("[api] no pude registrar api_bp: %r", e)

    # ---- fallback para /api/* si blueprint no cargó ----
    if not api_loaded:
        @app.route("/api/<path:_rest>", methods=["GET","POST","HEAD","OPTIONS"])
        def _api_unavailable(_rest: str):
            if request.method == "OPTIONS":
                # Preflight CORS estricto
                return _apply_cors_headers(app.make_response(("", 204)))
            # Error JSON consistente
            resp = app.make_response((jsonify(error="API routes not loaded"), 503))
            return _apply_cors_headers(resp)

    return app

# Export estándar para Gunicorn
application = create_app()
'''
code = textwrap.dedent(code).lstrip()
io.open(p, "w", encoding="utf-8").write(code)
print("[factory] __init__.py reescrito OK")
PY

# Verificación de sintaxis
python -m py_compile backend/__init__.py && echo "[factory] py_compile OK"
