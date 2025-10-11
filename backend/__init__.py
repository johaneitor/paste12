import os
import logging
from flask import Flask, jsonify, request
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

db = SQLAlchemy()

# Global rate limiter (initialized in create_app)
# Default policy aligned with spec: 300 requests per hour for general GETs
limiter: Limiter = Limiter(key_func=get_remote_address, default_limits=["300 per hour"]) 

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
    # Expose permissive CORS for API endpoints and allow custom headers like X-FP
    CORS(app, resources={r"/api/*": {"origins": "*"}}, supports_credentials=False)

    # --- SQLAlchemy init ---
    db.init_app(app)

    # --- Rate limit storage config (prefer Redis in prod) ---
    try:
        app.config.setdefault("RATELIMIT_STORAGE_URI", os.environ.get("FLASK_LIMITER_STORAGE_URI") or "memory://")
    except Exception:
        pass

    # --- Ensure minimal schema (non-intrusive) ---
    try:
        with app.app_context():
            # Ensure core models are loaded so create_all() is aware
            from . import models as _models  # noqa: F401
            # Create tables for declared models if missing (e.g., notes)
            db.create_all()

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
            db.session.execute(_text(
                """
                CREATE TABLE IF NOT EXISTS note_view (
                  note_id INTEGER NOT NULL,
                  fp TEXT NOT NULL,
                  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                  UNIQUE(note_id, fp)
                )
                """
            ))
            db.session.execute(_text(
                """
                CREATE TABLE IF NOT EXISTS note_like (
                  note_id INTEGER NOT NULL,
                  fp TEXT NOT NULL,
                  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                  UNIQUE(note_id, fp)
                )
                """
            ))
            # Add deleted_at column if missing (best-effort for both notes/note)
            for tbl in ("notes", "note"):
                try:
                    db.session.execute(_text(f"ALTER TABLE {tbl} ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP NULL"))
                except Exception:
                    # SQLite older versions don't support IF NOT EXISTS; try plain add
                    try:
                        db.session.execute(_text(f"ALTER TABLE {tbl} ADD COLUMN deleted_at TIMESTAMP NULL"))
                    except Exception:
                        pass
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

    # --- Canonical alias endpoint for /api/report (takes precedence) ---
    @app.route("/api/report", methods=["GET", "POST"])
    def _report_alias_canonical():
        # Legacy alias disabled: always respond 404 to avoid legacy handlers.
        return jsonify(error="not_found"), 404

    # --- Legacy like alias to homogenize negatives ---
    @app.route("/api/like", methods=["GET", "POST"])  # ensure 404/405 similar to view/report
    def _like_alias_canonical():
        # Require numeric id like other aliases; otherwise respond 404
        nid = (request.args.get("id") if request.method == "GET" else (request.get_json(silent=True) or {}).get("id"))
        try:
            nid_int = int(nid)
        except Exception:
            return jsonify(error="not_found"), 404
        # We don't implement side-effects here; this legacy alias is disabled
        return jsonify(error="not_found"), 404

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

        # Guardar el detalle en una variable local (el binding del 'exc' de except
        # se limpia tras salir del bloque en Python 3). Evitamos capturar 'exc'.
        _api_fallback_detail = str(exc)

        @app.route("/api/health")
        def _health_fallback():
            # Do not leak internal exception details unless explicitly enabled
            body = {"ok": True, "api": False, "ver": "factory-fallback"}
            if os.environ.get("P12_HEALTH_DETAIL", "0") == "1":
                body["detail"] = _api_fallback_detail
            resp = jsonify(**body)
            try:
                resp.headers["Cache-Control"] = "no-store"
            except Exception:
                pass
            return resp, 200

        # Asegurar que el health nunca sea limitado por tasa
        try:
            limiter.exempt(_health_fallback)
        except Exception:
            pass

        # No definir fallback de /api/notes aquí para permitir que la cápsula
        # de notas se registre más abajo si está disponible.

    # --- Asegurar /api/notes mínimo si falta ---
    try:
        from .routes_notes import register_api as _register_notes  # type: ignore
        _register_notes(app)
    except Exception as _e:
        app.logger.warning("[api] notes capsule not registered: %r", _e)

    # --- Registrar interacciones (like/view/report) si el módulo está disponible ---
    try:
        from .modules.interactions import register_into as _register_interactions  # type: ignore
        _register_interactions(app)
    except Exception as _e:
        app.logger.warning("[api] interactions not registered: %r", _e)

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
    @limiter.exempt
    def api_health():
        resp = jsonify(ok=True, status="ok", api=True, ver="factory-min-v1")
        try:
            resp.headers["Cache-Control"] = "no-store"
        except Exception:
            pass
        return resp, 200

    # Alias mínimo independiente para health checks de la plataforma
    @app.get("/healthz")
    @limiter.exempt
    def healthz():
        resp = jsonify(ok=True)
        try:
            resp.headers["Cache-Control"] = "no-store"
        except Exception:
            pass
        return resp, 200

    # --- Health DB (opcional) ---
    @app.get("/api/health/db")
    def api_health_db():
        try:
            from sqlalchemy import text as _text
            with app.app_context():
                # simple round-trip (sqlite/pg compatible)
                db.session.execute(_text("SELECT 1"))
            return jsonify(ok=True, db=True), 200
        except Exception as exc:
            return jsonify(ok=False, db=False, error=str(exc)), 500

    # --- Uniform JSON error responses for /api/* ---
    @app.errorhandler(404)
    def _json_404(err):
        try:
            if request.path.startswith("/api/"):
                return jsonify(error="not_found"), 404
        except Exception:
            # Fall through to default HTML error page
            pass
        # For non-API routes, delegate to Flask's default 404 page
        return err

    @app.errorhandler(400)
    def _json_400(err):
        try:
            if request.path.startswith("/api/"):
                return jsonify(error="bad_request"), 400
        except Exception:
            # Fall through to default HTML error page
            pass
        # For non-API routes, delegate to Flask's default 400 page
        return err

    @app.errorhandler(405)
    def _json_405(err):
        try:
            if request.path.startswith("/api/"):
                # Include Allow header if available from exception
                resp = jsonify(error="method_not_allowed")
                try:
                    allow = getattr(err, "valid_methods", None)
                    if allow:
                        resp.headers["Allow"] = ", ".join(allow)
                except Exception:
                    pass
                return resp, 405
        except Exception:
            # Fall through to default HTML error page
            pass
        # For non-API routes, delegate to Flask's default 405 page
        return err

    # --- Optional secure headers (enable with P12_SECURE_HEADERS=1) ---
    if os.environ.get("P12_SECURE_HEADERS", "0") == "1":
        @app.after_request
        def _secure_headers(resp):
            try:
                resp.headers.setdefault("Strict-Transport-Security", "max-age=31536000; includeSubDomains; preload")
                resp.headers.setdefault("X-Frame-Options", "DENY")
                resp.headers.setdefault("X-Content-Type-Options", "nosniff")
                resp.headers.setdefault("Referrer-Policy", "no-referrer")
            except Exception:
                pass
            return resp

    return app
