#!/usr/bin/env bash
set -euo pipefail

TS="$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p tools/backups

# --- backend/__init__.py ---
if [[ -f backend/__init__.py ]]; then cp -f backend/__init__.py "tools/backups/__init__.py.$TS.bak"; fi
cat > backend/__init__.py <<'PY'
import os
from flask import Flask, jsonify
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
    @app.get("/api/health")
    def api_health():
        return jsonify(ok=True, api=True, ver="factory-min-v1")

    return app
PY

# --- backend/routes.py ---
if [[ -f backend/routes.py ]]; then cp -f backend/routes.py "tools/backups/routes.py.$TS.bak"; fi
cat > backend/routes.py <<'PY'
from flask import Blueprint, request, jsonify, Response, current_app
from sqlalchemy import text
from . import db

api_bp = Blueprint("api_bp", __name__)

@api_bp.route("/health", methods=["GET"])
def health():
    return jsonify(ok=True, api=True, ver="factory-min-v1")

@api_bp.route("/notes", methods=["OPTIONS"])
def notes_options():
    r = Response("", 204)
    r.headers["Access-Control-Allow-Origin"]  = "*"
    r.headers["Access-Control-Allow-Methods"] = "GET, POST, HEAD, OPTIONS"
    r.headers["Access-Control-Allow-Headers"] = "Content-Type"
    r.headers["Access-Control-Max-Age"]       = "86400"
    return r

@api_bp.route("/notes", methods=["GET"])
def get_notes():
    try:
        limit = min(int(request.args.get("limit", 10)), 50)
    except Exception:
        limit = 10
    before_id = request.args.get("before_id", type=int)

    sql = """
    SELECT id, text, timestamp, expires_at, likes, views, reports, author_fp
    FROM notes
    WHERE (:before_id IS NULL OR id < :before_id)
    ORDER BY id DESC
    LIMIT :limit
    """
    try:
        with db.session.begin():
            rows = db.session.execute(
                text(sql),
                {"before_id": before_id, "limit": limit},
            ).mappings().all()
        data = [dict(r) for r in rows]
        # Link header para paginación simple
        headers = {}
        if len(data) == limit and data:
            last_id = data[-1]["id"]
            headers["Link"] = f'</api/notes?limit={limit}&before_id={last_id}>; rel="next"'
        return jsonify(data), 200, headers
    except Exception as e:
        current_app.logger.exception("get_notes failed")
        return jsonify(error="db_error", detail=str(e)), 500

def _bump(col, note_id: int):
    sql = f"UPDATE notes SET {col} = COALESCE({col},0) + 1 WHERE id = :id RETURNING {col}"
    with db.session.begin():
        res = db.session.execute(text(sql), {"id": note_id}).first()
        return int(res[0]) if res else None

@api_bp.route("/notes/<int:note_id>/like", methods=["POST"])
def like_note(note_id: int):
    try:
        val = _bump("likes", note_id)
        return jsonify(ok=True, id=note_id, likes=val), 200
    except Exception as e:
        current_app.logger.exception("like failed")
        return jsonify(error="db_error", detail=str(e)), 500

@api_bp.route("/notes/<int:note_id>/view", methods=["POST"])
def view_note(note_id: int):
    try:
        val = _bump("views", note_id)
        return jsonify(ok=True, id=note_id, views=val), 200
    except Exception as e:
        current_app.logger.exception("view failed")
        return jsonify(error="db_error", detail=str(e)), 500

@api_bp.route("/notes/<int:note_id>/report", methods=["POST"])
def report_note(note_id: int):
    try:
        val = _bump("reports", note_id)
        return jsonify(ok=True, id=note_id, reports=val), 200
    except Exception as e:
        current_app.logger.exception("report failed")
        return jsonify(error="db_error", detail=str(e)), 500
PY

# --- backend/front_bp.py ---
if [[ -f backend/front_bp.py ]]; then cp -f backend/front_bp.py "tools/backups/front_bp.py.$TS.bak"; fi
cat > backend/front_bp.py <<'PY'
import os
from flask import Blueprint, send_from_directory, current_app

front_bp = Blueprint("front_bp", __name__)
BASE = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FRONT_DIR = os.path.join(BASE, "frontend")

@front_bp.route("/", methods=["GET"])
def index():
    p = os.path.join(FRONT_DIR, "index.html")
    if not os.path.isfile(p):
        current_app.logger.warning("frontend/index.html no encontrado, devolviendo fallback")
        return "<!doctype html><title>Paste12</title><h1>Paste12</h1>", 200
    return send_from_directory(FRONT_DIR, "index.html")

@front_bp.route("/terms", methods=["GET"])
def terms():
    f = "terms.html"
    return send_from_directory(FRONT_DIR, f) if os.path.isfile(os.path.join(FRONT_DIR, f)) else ("<h1>Términos</h1>", 200)

@front_bp.route("/privacy", methods=["GET"])
def privacy():
    f = "privacy.html"
    return send_from_directory(FRONT_DIR, f) if os.path.isfile(os.path.join(FRONT_DIR, f)) else ("<h1>Privacidad</h1>", 200)
PY

# --- wsgi.py ---
if [[ -f wsgi.py ]]; then cp -f wsgi.py "tools/backups/wsgi.py.$TS.bak"; fi
cat > wsgi.py <<'PY'
from backend import create_app  # type: ignore
application = create_app()
PY

python -m py_compile backend/__init__.py backend/routes.py backend/front_bp.py wsgi.py
echo "[factory-min] listo. Ahora: commit/push y en Render usa Start Command (una sola línea):"
echo "  gunicorn wsgi:application --chdir /opt/render/project/src -w \${WEB_CONCURRENCY:-2} -k gthread --threads \${THREADS:-4} --timeout \${TIMEOUT:-120} -b 0.0.0.0:\$PORT"
