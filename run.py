from __future__ import annotations
from flask import Flask, jsonify
import os

VER = "run-v3"  # marcador para distinguir este entrypoint

app = Flask(__name__)
app.config["SQLALCHEMY_DATABASE_URI"] = os.environ.get("DATABASE_URL", "sqlite:///app.db")
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

# --- DB (si existe backend.db) ---
db = None
try:
    from backend import db as _db
    _db.init_app(app)
    db = _db
except Exception as e:
    print("~ run: db.init_app skipped:", e)

# --- Registrar API (routes oficiales -> routes_notes -> fallback local) ---
api_src = None
try:
    from backend.routes import bp as api_bp
    app.register_blueprint(api_bp, url_prefix="/api")
    api_src = "backend.routes:bp"
except Exception as e1:
    try:
        from backend.routes_notes import register_api
        register_api(app)
        api_src = "backend.routes_notes:register_api"
    except Exception as e2:
        from flask import Blueprint, request
        from datetime import datetime, timedelta
        import hashlib

        api_bp = Blueprint("api", __name__)

        def _now(): return datetime.utcnow()
        def _fp(req: request) -> str:
            ip = req.headers.get("X-Forwarded-For","") or req.headers.get("CF-Connecting-IP","") or (req.remote_addr or "")
            ua = req.headers.get("User-Agent",""); salt = os.environ.get("FP_SALT","")
            return hashlib.sha256(f"{ip}|{ua}|{salt}".encode()).hexdigest()[:32]

        try:
            from backend.models import Note
        except Exception as e3:
            Note = None
            print("~ run: fallback sin models:", e3)

        @api_bp.get("/notes")
        def list_notes():
            if db is None or Note is None:
                return jsonify(error="fallback_missing_models"), 500
            page = max(1, int(request.args.get("page", 1) or 1))
            q = Note.query.order_by(Note.timestamp.desc())
            items = q.limit(20).offset((page-1)*20).all()
            now = _now()
            return jsonify([{
                "id": n.id, "text": n.text,
                "timestamp": n.timestamp.isoformat(),
                "expires_at": n.expires_at.isoformat() if n.expires_at else None,
                "likes": n.likes, "views": n.views, "reports": n.reports,
                "author_fp": getattr(n, "author_fp", None),
                "now": now.isoformat(),
            } for n in items]), 200

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
        api_src = "run_fallback:api_bp"

# --- Health con marcador y fuente del API ---
@app.get("/api/health")
def health():
    return jsonify(ok=True, note="run-app", ver=VER, api=bool(api_src), api_src=api_src)

# --- Auto create DB idempotente ---
try:
    if db is not None:
        with app.app_context():
            db.create_all()
            print("~ run: create_all OK")
except Exception as e:
    print("~ run: create_all failed:", e)

if __name__ == "__main__":
    host = os.environ.get("HOST", "0.0.0.0")
    port = int(os.environ.get("PORT", "8000"))
    app.run(host=host, port=port)
