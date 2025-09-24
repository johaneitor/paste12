#!/usr/bin/env bash
set -euo pipefail

ts="$(date -u +%Y%m%d-%H%M%SZ)"

backup(){ [[ -f "$1" ]] && cp -f "$1" "$1.$ts.bak" && echo "[backup] $1 -> $1.$ts.bak" || true; }

# 0) Respaldos
mkdir -p backend frontend tools
backup backend/__init__.py
backup backend/routes.py
backup backend/models.py
backup wsgi.py
backup contract_shim.py

# 1) __init__.py -> App Factory limpia (sin circular import)
cat > backend/__init__.py <<'PY'
from __future__ import annotations
import os, re
from flask import Flask, jsonify, send_from_directory
from flask_sqlalchemy import SQLAlchemy
from flask_cors import CORS

db = SQLAlchemy()

def _normalize_db_url(url: str) -> str:
    if not url: return url
    # postgres -> postgresql+psycopg2 (soporta Render)
    url = re.sub(r'^postgres(?=://)', 'postgresql+psycopg2', url)
    return url

def create_app() -> Flask:
    app = Flask(__name__, static_folder="../frontend", static_url_path="")
    # Config DB
    db_url = _normalize_db_url(os.environ.get("DATABASE_URL", ""))
    if db_url:
        app.config["SQLALCHEMY_DATABASE_URI"] = db_url
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

    # CORS abierto (como vienes testeando)
    CORS(app, resources={r"/api/*": {"origins": "*"}}, supports_credentials=False)

    # Inicializar DB
    db.init_app(app)

    # Registrar blueprint API
    from .routes import bp as api_bp
    app.register_blueprint(api_bp)

    # Health minimal sin DB
    @app.route("/api/health")
    def health():
        return jsonify({"ok": True, "api": True, "ver": "factory-v1"})

    # Servir el frontend (index.html) y estáticos
    @app.route("/")
    def index():
        return send_from_directory(app.static_folder, "index.html")

    return app

# Export para gunicorn
app = create_app()
PY
echo "[write] backend/__init__.py"

# 2) models.py – definición explícita de Note (evita import circular)
cat > backend/models.py <<'PY'
from __future__ import annotations
from datetime import datetime, timedelta
from sqlalchemy import func
from . import db

class Note(db.Model):
    __tablename__ = "notes"
    id = db.Column(db.Integer, primary_key=True)
    text = db.Column(db.Text, nullable=False)
    timestamp = db.Column(db.DateTime, nullable=False, default=func.now())
    expires_at = db.Column(db.DateTime, nullable=True)
    likes = db.Column(db.Integer, nullable=False, default=0)
    views = db.Column(db.Integer, nullable=False, default=0)
    reports = db.Column(db.Integer, nullable=False, default=0)
    author_fp = db.Column(db.String(64), nullable=True)

    def to_dict(self):
        return {
            "id": self.id,
            "text": self.text,
            "timestamp": (self.timestamp or datetime.utcnow()).isoformat(),
            "expires_at": self.expires_at.isoformat() if self.expires_at else None,
            "likes": self.likes,
            "views": self.views,
            "reports": self.reports,
            "author_fp": self.author_fp,
        }

    @staticmethod
    def default_ttl_hours() -> int:
        # 24h por defecto si no hay política distinta
        return 24

    @staticmethod
    def compute_expiry():
        return (datetime.utcnow() + timedelta(hours=Note.default_ttl_hours()))
PY
echo "[write] backend/models.py"

# 3) routes.py – blueprint con todas las rutas exigidas + Link header
cat > backend/routes.py <<'PY'
from __future__ import annotations
from flask import Blueprint, request, jsonify, current_app, Response
from sqlalchemy import desc
from typing import List
from . import db
from .models import Note

bp = Blueprint("api", __name__, url_prefix="/api")

def _as_json(obj, status=200, headers: dict | None = None):
    from flask import json
    r = current_app.response_class(
        response=json.dumps(obj, ensure_ascii=False),
        status=status,
        mimetype="application/json",
    )
    if headers:
        for k,v in headers.items():
            r.headers[k] = v
    # CORS headers consistentes
    r.headers.setdefault("Access-Control-Allow-Origin", "*")
    r.headers.setdefault("Access-Control-Allow-Methods", "GET, POST, HEAD, OPTIONS")
    r.headers.setdefault("Access-Control-Allow-Headers", "Content-Type")
    r.headers.setdefault("Access-Control-Max-Age", "86400")
    return r

@bp.route("/notes", methods=["OPTIONS"])
def notes_options():
    return _as_json("", status=204)

@bp.route("/notes", methods=["GET"])
def list_notes():
    # Paginación por before_id y limit (como venías testeando)
    try:
        limit = max(1, min(int(request.args.get("limit", "10")), 50))
    except Exception:
        limit = 10
    before_id = request.args.get("before_id")
    q = Note.query
    if before_id and before_id.isdigit():
        q = q.filter(Note.id < int(before_id))
    q = q.order_by(desc(Note.timestamp)).limit(limit)
    rows: List[Note] = q.all()
    body = [n.to_dict() for n in rows]

    # Link: next si hay más
    next_link = None
    if rows:
        last_id = rows[-1].id
        # ¿quedan más? comprobación rápida
        more = Note.query.filter(Note.id < last_id).order_by(desc(Note.timestamp)).first()
        if more:
            base = request.url_root.rstrip("/")
            next_link = f'<{base}/api/notes?limit={limit}&before_id={last_id}>; rel="next"'

    headers = {}
    if next_link:
        headers["Link"] = next_link

    return _as_json(body, 200, headers)

@bp.route("/notes", methods=["POST"])
def create_note():
    data = request.get_json(silent=True) or {}
    text = (data.get("text") if isinstance(data, dict) else None) or request.form.get("text") or ""
    text = text.strip()
    if not text:
        return _as_json({"error": "text requerido"}, 400)
    n = Note(text=text, expires_at=Note.compute_expiry())
    db.session.add(n)
    db.session.commit()
    return _as_json(n.to_dict(), 201)

def _act_on_note(note_id: int, field: str) -> Response:
    n = Note.query.get(note_id)
    if not n:
        return _as_json({"error": "not found"}, 404)
    setattr(n, field, int(getattr(n, field) or 0) + 1)
    db.session.commit()
    return _as_json({"ok": True, "id": n.id, field: getattr(n, field)})

@bp.route("/notes/<int:note_id>/like", methods=["POST"])
def like_note(note_id: int): return _act_on_note(note_id, "likes")

@bp.route("/notes/<int:note_id>/view", methods=["POST"])
def view_note(note_id: int): return _act_on_note(note_id, "views")

@bp.route("/notes/<int:note_id>/report", methods=["POST"])
def report_note(note_id: int): return _act_on_note(note_id, "reports")
PY
echo "[write] backend/routes.py"

# 4) wsgi.py – exportar WSGI estándar para Gunicorn
cat > wsgi.py <<'PY'
# WSGI entrypoint para Gunicorn
# Start Command en Render:
#   gunicorn wsgi:application --chdir /opt/render/project/src -w ${WEB_CONCURRENCY:-2} -k gthread --threads ${THREADS:-4} --timeout ${TIMEOUT:-120} -b 0.0.0.0:$PORT
from backend import app as application  # Gunicorn espera "application"
PY
echo "[write] wsgi.py"

# 5) (opcional) contract_shim: mantener export "application" por compatibilidad
python - <<'PY'
import io, re, os, sys, pathlib
p = pathlib.Path("contract_shim.py")
if p.exists():
    s = p.read_text(encoding="utf-8")
    if "application" not in s:
        s += "\n# compat: export application\nfrom backend import app as application\n"
        p.write_text(s, encoding="utf-8")
        print("[shim] application export añadido")
else:
    p.write_text("from backend import app as application\n", encoding="utf-8")
    print("[shim] creado contract_shim.py")
PY

# 6) py_compile sanity
python - <<'PY'
import py_compile, sys
for f in ("backend/__init__.py","backend/models.py","backend/routes.py","wsgi.py","contract_shim.py"):
    try:
        py_compile.compile(f, doraise=True)
        print(f"[compile] OK {f}")
    except Exception as e:
        print(f"[compile] FAIL {f}: {e}")
        sys.exit(1)
PY

echo "== backend_factory_reset_v1: listo =="
echo "Siguiente: despliega con el Start Command indicado y prueba."
