from __future__ import annotations

import os
import logging
from typing import Optional, Dict, Any

from flask import Flask, jsonify
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()


def _normalize_db_url(url: str) -> str:
    if url.startswith("postgres://"):
        url = url.replace("postgres://", "postgresql+psycopg2://", 1)
    # Fuerza SSL (Render PG suele requerirlo); evita duplicar si ya viene
    if "sslmode=" not in url:
        url += ("&" if "?" in url else "?") + "sslmode=require"
    return url


def create_app(config_override: Optional[Dict[str, Any]] = None) -> Flask:
    app = Flask(__name__, static_folder=None)

    # --- Config DB obligatoria ---
    db_url = (config_override or {}).get("SQLALCHEMY_DATABASE_URI") or os.getenv("DATABASE_URL", "")
    if not db_url:
        # Evita que Gunicorn “arranque” sin DB y dé 500s opacos
        raise RuntimeError("DATABASE_URL no está definido (requerido).")

    app.config.update(
        SQLALCHEMY_DATABASE_URI=_normalize_db_url(db_url),
        SQLALCHEMY_TRACK_MODIFICATIONS=False,
        JSON_SORT_KEYS=False,
        # Motor: defensivo frente a cortes/SSL
        SQLALCHEMY_ENGINE_OPTIONS=dict(
            pool_pre_ping=True,
            pool_recycle=int(os.getenv("SQL_POOL_RECYCLE", "180")),
            pool_size=int(os.getenv("SQL_POOL_SIZE", "5")),
            max_overflow=int(os.getenv("SQL_MAX_OVERFLOW", "5")),
            pool_timeout=int(os.getenv("SQL_POOL_TIMEOUT", "30")),
        ),
    )

    # Extensiones
    db.init_app(app)
    CORS(app)  # CORS sencillo para /api/*

    # Health básico del factory (si fallan rutas, esto sigue vivo)
    @app.get("/api/health")
    def _health():
        return jsonify(ok=True, api=False, ver="factory-v6")

    # Registro de rutas API real, con fallback limpio
    try:
        from .routes import api_bp  # type: ignore
        app.register_blueprint(api_bp)
        # Re-declare /api/health indicando que estamos con API real:
        @app.get("/api/health")
        def _health_api():
            return jsonify(ok=True, api=True, ver="api-routes-v1")
    except Exception as e:
        logging.exception("[api] fallo registrando api_bp; habilitando fallback")
        err_text = str(e)

        @app.get("/api/notes")
        def _api_unavailable_notes():
            return jsonify(error="API routes not available", detail=err_text), 500

    # Raíz: no tocamos '/', lo sirve tu frontend/blueprint/estático actual
    return app
