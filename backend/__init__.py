import os
from flask import Flask, jsonify
import os, time
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()

def create_app():
    app = Flask(__name__)

    # --- DB URL (con fallback) ---
    db_url = os.environ.get("DATABASE_URL") or os.environ.get("SQLALCHEMY_DATABASE_URI")
    if db_url and db_url.startswith("postgres://"):
        db_url = db_url.replace("postgres://", "postgresql://", 1)
    app.config["SQLALCHEMY_DATABASE_URI"] = db_url or "sqlite:////tmp/paste12.db"
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

    # --- CORS sólo para /api/* ---
    CORS(app, resources={r"/api/*": {"origins": "*"}})

    # --- SQLAlchemy init ---
    db.init_app(app)

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
    _start_ts = time.time()
    @app.get("/api/health")
    def api_health():
        # status 200 estable, incluye commit y uptime
        commit = None
        for k in ("RENDER_GIT_COMMIT","GIT_COMMIT","SOURCE_COMMIT","COMMIT_SHA"):
            v = os.environ.get(k)
            if v:
                commit = v
                break
        # db status
        try:
            db.session.execute("SELECT 1")
            db_status = "ok"
        except Exception:
            db_status = "degraded"
        return jsonify(status="ok", commit=commit, db=db_status, uptime_seconds=int(time.time()-_start_ts))

    return app
