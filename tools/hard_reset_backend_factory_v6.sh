#!/usr/bin/env bash
set -euo pipefail
TS="$(date -u +%Y%m%d-%H%M%SZ)"
P="backend/__init__.py"
[[ -f "$P" ]] && cp -f "$P" "${P}.${TS}.bak" || true
cat > "$P" <<'PY'
from __future__ import annotations

import os, logging, re
from typing import Any, Dict
from flask import Flask, jsonify, request, send_from_directory
from flask_cors import CORS
from werkzeug.exceptions import HTTPException
from flask_sqlalchemy import SQLAlchemy

# --- DB base (dejar global para modelos) ---
db = SQLAlchemy()

def _normalize_db_url(u: str | None) -> str | None:
    if not u: 
        return None
    return re.sub(r'^postgres://', 'postgresql://', u)

def _config_app(app: Flask) -> None:
    uri = _normalize_db_url(os.getenv("DATABASE_URL") or app.config.get("SQLALCHEMY_DATABASE_URI"))
    if uri:
        app.config["SQLALCHEMY_DATABASE_URI"] = uri
    # Pool conservative y seguro
    app.config.setdefault("SQLALCHEMY_ENGINE_OPTIONS", {
        "pool_pre_ping": True,
        "pool_recycle": 300,
        "pool_size": 5,
        "max_overflow": 5,
    })
    app.config.setdefault("SQLALCHEMY_TRACK_MODIFICATIONS", False)

def _make_fallback_api_bp(err: Exception):
    from flask import Blueprint
    bp = Blueprint("api_fallback", __name__)

    @bp.get("/health")
    def health():
        return jsonify(ok=True, api=False, ver="factory-v6", diag=str(err))

    @bp.get("/notes")
    def notes_fallback():
        # Importante: devolver 404 real, NO 500
        return jsonify(error="not_found", detail="API routes not loaded"), 404

    return bp

def _register_front_bp(app: Flask) -> None:
    """
    Sirve el index/legales si existe front_bp; si no, sirve archivos de ./frontend
    """
    try:
        from .front_serve import front_bp  # opcional
        app.register_blueprint(front_bp)
        app.logger.info("[front] front_bp registrado")
    except Exception as e:
        app.logger.warning("[front] front_bp no disponible: %s. Sirviendo ./frontend", e)
        # Servido plano desde ./frontend si existe
        FRONT_DIR = os.path.join(os.path.dirname(__file__), "..", "frontend")
        FRONT_DIR = os.path.abspath(FRONT_DIR)

        @app.get("/")
        def _root():
            idx = os.path.join(FRONT_DIR, "index.html")
            if os.path.exists(idx):
                return send_from_directory(FRONT_DIR, "index.html")
            return "<h1>Paste12</h1><p>Frontend no encontrado.</p>", 200

        @app.get("/terms")
        def _terms():
            f = os.path.join(FRONT_DIR, "terms.html")
            if os.path.exists(f):
                return send_from_directory(FRONT_DIR, "terms.html")
            return "<h1>Términos</h1>", 200

        @app.get("/privacy")
        def _privacy():
            f = os.path.join(FRONT_DIR, "privacy.html")
            if os.path.exists(f):
                return send_from_directory(FRONT_DIR, "privacy.html")
            return "<h1>Privacidad</h1>", 200

def create_app() -> Flask:
    app = Flask(__name__, static_url_path=None)
    CORS(app)
    _config_app(app)
    # Inicializar DB si hay URI
    if app.config.get("SQLALCHEMY_DATABASE_URI"):
        db.init_app(app)

    # === API ===
    api_ok = False
    try:
        # Preferimos blueprint externo
        from .routes import api_bp  # debe definir /api/notes, /api/health, etc.
        app.register_blueprint(api_bp, url_prefix="/api")
        api_ok = True
        app.logger.info("[api] api_bp registrado")
    except Exception as e:
        app.logger.exception("[api] fallo registrando api_bp, cargando fallback")
        app.register_blueprint(_make_fallback_api_bp(e), url_prefix="/api")

    # Health siempre disponible y ver incluye si API está OK
    @app.get("/api/health")
    def _health():
        # detecta si /api/notes existe
        routes = {r.rule for r in app.url_map.iter_rules()}
        has_notes = "/api/notes" in routes
        return jsonify(ok=True, api=has_notes, ver="factory-v6")

    # === FRONT ===
    _register_front_bp(app)

    # === Handlers: respetar HTTPException (404, 405) ===
    @app.errorhandler(Exception)
    def _on_error(e: Exception):
        if isinstance(e, HTTPException):
            # Respetar el código original (ej: 404)
            return jsonify(error=e.name, detail=e.description), e.code
        app.logger.exception("Unhandled error")
        return jsonify(error="internal_error"), 500

    # Log de rutas para diagnóstico
    try:
        for r in sorted(app.url_map.iter_rules(), key=lambda x: x.rule):
            app.logger.info("[route] %s %s", ",".join(r.methods), r.rule)
    except Exception:
        pass

    return app

# Para gunicorn: wsgi:application
application = create_app()
PY

python -m py_compile "$P" && echo "py_compile OK: $P"
echo "[hard-reset] Listo. Sugerido: redeploy con Start Command de gunicorn estándar."
