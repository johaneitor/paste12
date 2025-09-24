#!/usr/bin/env bash
set -euo pipefail

ts="$(date -u +%Y%m%d-%H%M%SZ)"
backup() { [[ -f "$1" ]] && cp -f "$1" "$1.$ts.bak" && echo "[backup] $1 -> $1.$ts.bak" || true; }

mkdir -p backend frontend tools

# --- backend/__init__.py (app factory SIN imports cruzados) ---
backup backend/__init__.py
cat > backend/__init__.py <<'PY'
from __future__ import annotations
import os
from flask import Flask, jsonify, send_from_directory
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()

def _normalize_db_uri(uri: str) -> str:
    if uri.startswith("postgres://"):
        return uri.replace("postgres://", "postgresql+psycopg2://", 1)
    if uri.startswith("postgresql://"):
        return uri.replace("postgresql://", "postgresql+psycopg2://", 1)
    return uri

def create_app() -> Flask:
    app = Flask(__name__, static_folder="../frontend", static_url_path="/")
    uri = os.getenv("DATABASE_URL") or os.getenv("DATABASE_URI") or "sqlite:///local.db"
    app.config["SQLALCHEMY_DATABASE_URI"] = _normalize_db_uri(uri)
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    app.config["JSON_SORT_KEYS"] = False

    # DB + CORS
    db.init_app(app)
    CORS(app, resources={r"/api/*": {"origins": "*"}}, expose_headers=["Link"], max_age=86400)

    # Health temprano (no toca DB)
    @app.get("/api/health")
    def health():
        return jsonify(ok=True, api=True, ver="clean-init-v1")

    # Registrar rutas DESPUÉS de init_app para evitar ciclos
    from .routes import api_bp  # import local para no formar ciclo
    app.register_blueprint(api_bp)

    # Index estático
    @app.get("/")
    def index_page():
        return send_from_directory(app.static_folder, "index.html")

    # Crear tablas si no existen (no rompe en Postgres si ya están)
    try:
        with app.app_context():
            db.create_all()
    except Exception:
        # No hacemos ruido en prod (p.ej. roles limitados o migraciones externas)
        pass

    return app

# Exponer WSGI por compatibilidad con gunicorn wsgi:application
app = create_app()
PY

# --- backend/models.py ---
backup backend/models.py
cat > backend/models.py <<'PY'
from __future__ import annotations
from datetime import datetime, timedelta
from . import db

def default_exp():
    return datetime.utcnow() + timedelta(days=1)

class Note(db.Model):
    __tablename__ = "notes"
    id         = db.Column(db.Integer, primary_key=True)
    text       = db.Column(db.Text, nullable=False)
    timestamp  = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    expires_at = db.Column(db.DateTime, nullable=False, default=default_exp)
    likes      = db.Column(db.Integer, nullable=False, default=0)
    views      = db.Column(db.Integer, nullable=False, default=0)
    reports    = db.Column(db.Integer, nullable=False, default=0)
    author_fp  = db.Column(db.String(64), nullable=False, default="")
PY

# --- backend/routes.py (Blueprint, CORS, Link header, JSON/FORM, negativos) ---
backup backend/routes.py
cat > backend/routes.py <<'PY'
from __future__ import annotations
from flask import Blueprint, request, jsonify
from datetime import datetime, timedelta
from sqlalchemy.exc import SQLAlchemyError, OperationalError
from .models import Note
from . import db

api_bp = Blueprint("api", __name__, url_prefix="/api")

@api_bp.after_request
def _cors_headers(resp):
    resp.headers.setdefault("Access-Control-Allow-Origin", "*")
    resp.headers.setdefault("Access-Control-Allow-Methods", "GET, POST, HEAD, OPTIONS")
    resp.headers.setdefault("Access-Control-Allow-Headers", "Content-Type")
    resp.headers.setdefault("Access-Control-Max-Age", "86400")
    return resp

@api_bp.route("/notes", methods=["OPTIONS"])
def notes_options():
    return ("", 204)

@api_bp.get("/notes")
def list_notes():
    try:
        limit = min(max(int(request.args.get("limit", 10)), 1), 50)
    except Exception:
        limit = 10
    before_id = request.args.get("before_id", type=int)

    q = Note.query
    if before_id:
        q = q.filter(Note.id < before_id)
    rows = q.order_by(Note.id.desc()).limit(limit).all()

    data = []
    now = datetime.utcnow()
    for n in rows:
        data.append({
            "id": n.id,
            "text": n.text,
            "timestamp": n.timestamp.isoformat(),
            "expires_at": (n.expires_at or (n.timestamp + timedelta(days=1))).isoformat(),
            "likes": n.likes,
            "views": n.views,
            "reports": n.reports,
            "author_fp": n.author_fp,
            "now": now.isoformat(),
        })

    from flask import current_app, url_for
    resp = jsonify(data)
    if rows:
        next_before = rows[-1].id
        # Construimos URL absoluta a mano (url_for con _external requiere SERVER_NAME)
        base = request.url_root.rstrip("/")
        resp.headers["Link"] = f'<{base}/api/notes?limit={limit}&before_id={next_before}>; rel="next"'
    return resp, 200

@api_bp.post("/notes")
def create_note():
    try:
        text = ""
        if request.is_json:
            payload = request.get_json(silent=True) or {}
            text = (payload.get("text") or "").strip()
        else:
            text = (request.form.get("text") or "").strip()
        if not text:
            return jsonify(error="text required"), 400
        n = Note(text=text)
        db.session.add(n)
        db.session.commit()
        return jsonify(ok=True, id=n.id), 201
    except (SQLAlchemyError, OperationalError):
        db.session.rollback()
        return jsonify(error="db error"), 503

def _bump(field: str, note_id: int):
    n = Note.query.get(note_id)
    if not n:
        return None
    setattr(n, field, int(getattr(n, field) or 0) + 1)
    db.session.commit()
    return n

@api_bp.post("/notes/<int:note_id>/like")
def like_note(note_id: int):
    try:
        n = _bump("likes", note_id)
        return (jsonify(error="not found"), 404) if n is None else (jsonify(ok=True, likes=n.likes), 200)
    except (SQLAlchemyError, OperationalError):
        db.session.rollback()
        return jsonify(error="db error"), 503

@api_bp.post("/notes/<int:note_id>/view")
def view_note(note_id: int):
    try:
        n = _bump("views", note_id)
        return (jsonify(error="not found"), 404) if n is None else (jsonify(ok=True, views=n.views), 200)
    except (SQLAlchemyError, OperationalError):
        db.session.rollback()
        return jsonify(error="db error"), 503

@api_bp.post("/notes/<int:note_id>/report")
def report_note(note_id: int):
    try:
        n = _bump("reports", note_id)
        return (jsonify(error="not found"), 404) if n is None else (jsonify(ok=True, reports=n.reports), 200)
    except (SQLAlchemyError, OperationalError):
        db.session.rollback()
        return jsonify(error="db error"), 503
PY

# --- wsgi.py (exponer application directo desde backend) ---
backup wsgi.py
cat > wsgi.py <<'PY'
from __future__ import annotations
try:
    # Si el módulo ya expone app, úsalo
    from backend import app as application  # type: ignore
except Exception:
    # Fallback a create_app
    from backend import create_app  # type: ignore
    application = create_app()
PY

# Compilar rápido
python -m py_compile backend/__init__.py backend/models.py backend/routes.py wsgi.py
echo "OK: backend limpio aplicado y compilado."
