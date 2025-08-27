from __future__ import annotations
import os, hashlib
from datetime import datetime, timedelta
from flask import Flask, jsonify, request

VER = "wsgi-v3"
api_src: str | None = None

# Construcción de app
try:
    from backend import create_app, db  # db = SQLAlchemy() dentro del paquete
    app: Flask = create_app()
except Exception as e:
    # Fallback: app mínima
    app = Flask(__name__)
    app.config["SQLALCHEMY_DATABASE_URI"] = os.environ.get("DATABASE_URL", "sqlite:///app.db")
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    try:
        from flask_sqlalchemy import SQLAlchemy
        db = SQLAlchemy()
        db.init_app(app)
    except Exception as e2:
        db = None
        print("~ wsgi: SQLAlchemy no disponible:", e2)

# ¿Ya hay /api/health registrado?
def _has_rule(rule: str, method: str = "GET") -> bool:
    try:
        for r in app.url_map.iter_rules():
            if str(r) == rule and method.upper() in r.methods:
                return True
    except Exception:
        pass
    return False

# Registrar API real (si existe) o fallback mínimo
try:
    from backend.routes import bp as api_bp  # blueprint "api"
    app.register_blueprint(api_bp, url_prefix="/api")
    api_src = "backend.routes:bp"
except Exception as e1:
    try:
        from backend.routes_notes import register_api
        register_api(app)  # registra /api/notes
        api_src = "backend.routes_notes:register_api"
    except Exception as e2:
        # Fallback mínimo (requiere modelos si queremos persistir)
        try:
            from backend.models import Note  # usa backend.db
        except Exception as e3:
            Note = None

        from flask import Blueprint
        api_bp = Blueprint("api", __name__)

        def _now(): return datetime.utcnow()
        def _fp(req: request) -> str:
            ip = req.headers.get("X-Forwarded-For","") or req.headers.get("CF-Connecting-IP","") or (req.remote_addr or "")
            ua = req.headers.get("User-Agent",""); salt = os.environ.get("FP_SALT","")
            return hashlib.sha256(f"{ip}|{ua}|{salt}".encode()).hexdigest()[:32]

        @api_bp.get("/notes")
        def list_notes():
            if db is None or Note is None:
                return jsonify(error="fallback_missing_models"), 500
            page = max(1, int(request.args.get("page", 1) or 1))
            q = Note.query.order_by(Note.timestamp.desc())
            items = q.limit(20).offset((page-1)*20).all()
            now = _now()
            out = []
            for n in items:
                out.append({
                    "id": n.id, "text": n.text,
                    "timestamp": n.timestamp.isoformat(),
                    "expires_at": n.expires_at.isoformat() if n.expires_at else None,
                    "likes": n.likes, "views": n.views, "reports": n.reports,
                    "author_fp": getattr(n, "author_fp", None),
                    "now": now.isoformat(),
                })
            return jsonify(out), 200

        @api_bp.post("/notes")
        def create_note():
            if db is None or Note is None:
                return jsonify(error="fallback_missing_models"), 500
            data = request.get_json(silent=True) or {}
            text = (data.get("text") or "").strip()
            if not text:
                return jsonify(error="text required"), 400
            try:
                hours = int(data.get("hours", 24))
            except Exception:
                hours = 24
            hours = min(168, max(1, hours))
            now = _now()
            n = Note(
                text=text, timestamp=now,
                expires_at=now + timedelta(hours=hours),
                author_fp=_fp(request)
            )
            db.session.add(n)
            db.session.commit()
            return jsonify({
                "id": n.id, "text": n.text,
                "timestamp": n.timestamp.isoformat(),
                "expires_at": n.expires_at.isoformat() if n.expires_at else None,
                "likes": n.likes, "views": n.views, "reports": n.reports,
                "author_fp": getattr(n, "author_fp", None),
                "now": now.isoformat(),
            }), 201

        app.register_blueprint(api_bp, url_prefix="/api")
        api_src = "wsgi_fallback:api_bp"

# Health con marcador si no existe
if not _has_rule("/api/health", "GET"):
    @app.get("/api/health")
    def _health():
        return jsonify(ok=True, note="wsgiapp", ver=VER, api=bool(api_src), api_src=api_src)

# create_all si tenemos db y modelos
try:
    if "sqlite" in app.config.get("SQLALCHEMY_DATABASE_URI", "") and "check_same_thread" not in app.config.get("SQLALCHEMY_DATABASE_URI",""):
        # nada especial; SQLite local por defecto
        pass
    if 'backend.models' not in globals():
        try:
            import backend.models  # registra tablas
        except Exception as _e:
            pass
    if 'db' in globals() and db is not None:
        with app.app_context():
            db.create_all()
            print("~ wsgi: create_all OK")
except Exception as e:
    print("~ wsgi: create_all failed:", e)
