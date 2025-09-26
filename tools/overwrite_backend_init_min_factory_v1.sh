#!/usr/bin/env bash
set -euo pipefail

INI="backend/__init__.py"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p backend
[[ -f "$INI" ]] && cp -f "$INI" "$INI.$TS.bak" && echo "[backup] $INI.$TS.bak"

cat > "$INI" <<'PY'
from __future__ import annotations

import os
from flask import Flask, jsonify, request, current_app
from flask_cors import CORS

# Nota: NO importamos models/db a nivel módulo para evitar ciclos.

def _api_unavailable(e: Exception):
    """Handler seguro para errores en /api/*"""
    try:
        current_app.logger.exception("API error on %s %s", request.method, request.path)
    except Exception:
        pass
    return jsonify(error="internal_error", detail=str(e)), 500


def create_app() -> Flask:
    app = Flask(__name__)

    # Config DB básica si viene de env y no está seteada explícitamente
    if not app.config.get("SQLALCHEMY_DATABASE_URI") and os.getenv("DATABASE_URL"):
        app.config["SQLALCHEMY_DATABASE_URI"] = os.environ["DATABASE_URL"]

    # CORS para /api/*
    CORS(
        app,
        resources={r"/api/*": {"origins": "*"}},
        methods=["GET", "POST", "HEAD", "OPTIONS"],
        allow_headers=["Content-Type"],
        max_age=86400,
    )

    # Registrar blueprint del frontend si existe (no falla si falta)
    try:
        from .front_serve import front_bp  # opcional
        app.register_blueprint(front_bp)
    except Exception:
        pass

    # Registrar rutas API si existen (no rompe si no están)
    try:
        from .routes import bp as api_bp  # opcional
        app.register_blueprint(api_bp)
    except Exception as e:
        try:
            app.logger.warning("routes no cargadas: %r", e)
        except Exception:
            pass

    # Safeguards universales (OPTIONS 204 + GET fallback /api/notes)
    try:
        from .safeguards import register_api_safeguards
        register_api_safeguards(app)
    except Exception as e:
        try:
            app.logger.warning("safeguards no activos: %r", e)
        except Exception:
            pass

    # Health estable
    @app.get("/api/health")
    def _health():
        return jsonify(ok=True, api=True, ver="factory-v6")

    # Handler global de errores para mantener forma JSON en /api/*
    @app.errorhandler(Exception)
    def _any_error(e: Exception):
        # Para peticiones /api/* retornamos forma JSON; si no, dejamos que Flask sirva HTML
        try:
            if request.path.startswith("/api/"):
                return _api_unavailable(e)
        except Exception:
            pass
        # fuera de /api, que Flask decida (HTML)
        raise e

    return app
PY

python -m py_compile "$INI"
echo "[ok] __init__.py escrito y compilado"

echo "Sugerido:"
echo "  tools/smoke_api_notes_v7.sh \"https://paste12-rmsk.onrender.com\" \"/sdcard/Download\""
