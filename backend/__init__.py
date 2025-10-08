import os
import logging
from flask import Flask, jsonify, request
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

db = SQLAlchemy()

# Global rate limiter (initialized in create_app)
limiter: Limiter = Limiter(key_func=get_remote_address, default_limits=["200 per minute"]) 

def create_app():
    app = Flask(__name__)

    # --- DB URL (con fallback) ---
    db_url = os.environ.get("DATABASE_URL") or os.environ.get("SQLALCHEMY_DATABASE_URI")
    if db_url and db_url.startswith("postgres://"):
        db_url = db_url.replace("postgres://", "postgresql://", 1)
    app.config["SQLALCHEMY_DATABASE_URI"] = db_url or "sqlite:////tmp/paste12.db"
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    app.config.setdefault("SQLALCHEMY_ENGINE_OPTIONS", {
        "pool_pre_ping": True,
        "pool_recycle": 280,
    })

    # --- CORS sólo para /api/* ---
    CORS(app, resources={r"/api/*": {"origins": "*"}})

    # --- SQLAlchemy init ---
    db.init_app(app)

    # --- Ensure minimal schema (non-intrusive) ---
    try:
        with app.app_context():
            from sqlalchemy import text as _text
            db.session.execute(_text(
                """
                CREATE TABLE IF NOT EXISTS note_report (
                  note_id INTEGER NOT NULL,
                  reporter_hash TEXT NOT NULL,
                  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                  UNIQUE(note_id, reporter_hash)
                )
                """
            ))
            db.session.commit()
    except Exception as _exc:
        logging.getLogger(__name__).warning("[schema] ensure note_report skipped: %r", _exc)

    # --- Early guard for legacy alias /api/report to ensure 404 on bad/missing id ---
    @app.before_request
    def _guard_alias_report_early():
        try:
            if request.path == "/api/report" and request.method in ("GET", "POST"):
                raw = request.args.get("id") or request.form.get("id")
                if not raw:
                    return jsonify(error="bad_id"), 404
                try:
                    int(raw)
                except Exception:
                    return jsonify(error="bad_id"), 404
        except Exception:
            # Do not block request flow on guard exception
            return None

    # --- Rate limiter (default 200/min global) ---
    try:
        # In production you should configure FLASK_LIMITER_STORAGE_URI (e.g., redis://)
        # to avoid in-memory storage.
        limiter.init_app(app)
    except Exception as exc:
        logging.getLogger(__name__).warning("[limiter] init failed: %r", exc)

    # --- API (si falla import, queda fallback limpio) ---
    try:
        from .routes import api_bp  # type: ignore
        app.register_blueprint(api_bp, url_prefix="/api")
    except Exception as exc:
        app.logger.error("[api] fallback: no pude registrar api_bp: %r", exc)

        @app.route("/api/health")
        def _health_fallback():
            return jsonify(ok=True, api=False, ver="factory-fallback", detail=str(exc)), 200

        @app.route("/api/notes", methods=["GET", "POST", "OPTIONS"])
        def _notes_unavail():
            return jsonify(error="API routes not loaded", detail=str(exc)), 500

    # --- Frontend blueprint (sirve /, /terms, /privacy) ---
    try:
        from .front_bp import front_bp  # type: ignore
        app.register_blueprint(front_bp)
    except Exception as exc:
        app.logger.warning("[front] blueprint no registrado: %r", exc)

        @app.route("/")
        def _index_min():
            return "<!doctype html><title>Paste12</title><h1>Paste12</h1>", 200

    # --- Health mínimo (si ya existe en api_bp, este no molesta) ---
    @app.get("/api/health")
    def api_health():
        return jsonify(ok=True, status="ok", api=True, ver="factory-min-v1")

    return app
