#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"
RENDER_URL="${RENDER_URL:-https://paste12-rmsk.onrender.com}"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"

mkdir -p backend

############################################
# 1) Fallback API mínimo (si falla registrar bp real)
############################################
cat > backend/api.py <<'PY'
from __future__ import annotations
from flask import Blueprint, jsonify, request
from datetime import datetime, timedelta
import os, hashlib

api = Blueprint("api", __name__)

try:
    from backend import db
    from backend.models import Note
except Exception as e:
    db = None
    Note = None
    print("~ backend.api: no pude importar db/Note:", e)

def _now() -> datetime: return datetime.utcnow()

def _fp() -> str:
    try:
        ip = request.headers.get("X-Forwarded-For","") or request.headers.get("CF-Connecting-IP","") or (request.remote_addr or "")
        ua = request.headers.get("User-Agent","")
    except Exception: return "noctx"
    salt = os.environ.get("FP_SALT","")
    return hashlib.sha256(f"{ip}|{ua}|{salt}".encode()).hexdigest()[:32]

@api.get("/notes")
def list_notes():
    if Note is None or db is None:
        return jsonify(error="backend_api_fallback_missing_models"), 500
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

@api.post("/notes")
def create_note():
    if Note is None or db is None:
        return jsonify(error="backend_api_fallback_missing_models"), 500
    data = request.get_json(silent=True) or {}
    text = (data.get("text") or "").strip()
    if not text: return jsonify(error="text required"), 400
    try: hours = int(data.get("hours", 24))
    except Exception: hours = 24
    hours = min(168, max(1, hours))
    now = _now()
    try:
        n = Note(
            text=text, timestamp=now,
            expires_at=now + timedelta(hours=hours),
            author_fp=_fp()
        )
        db.session.add(n); db.session.commit()
        return jsonify({
            "id": n.id, "text": n.text,
            "timestamp": n.timestamp.isoformat(),
            "expires_at": n.expires_at.isoformat() if n.expires_at else None,
            "likes": n.likes, "views": n.views, "reports": n.reports,
            "author_fp": getattr(n, "author_fp", None),
            "now": now.isoformat(),
        }), 201
    except Exception as e:
        db.session.rollback()
        return jsonify(error="create_failed", detail=str(e)), 500
PY

############################################
# 2) WSGI con registro robusto del API + health con marker
############################################
cat > wsgi.py <<'PY'
from __future__ import annotations
import os
from flask import Flask, jsonify, send_from_directory

VER = "wsgi-v2"  # marcador para verificar despliegue

app = Flask(__name__, static_folder="public", static_url_path="")
app.config["SQLALCHEMY_DATABASE_URI"] = os.environ.get("DATABASE_URL", "sqlite:///app.db")
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

# Inicializar DB si backend expone 'db'
db = None
try:
    from backend import db as _db
    _db.init_app(app)
    db = _db
except Exception as e:
    print("~ wsgi: db.init_app skipped:", e)

def _register_api(app) -> str | None:
    # 1) Intentar blueprint oficial backend.routes:bp
    try:
        from backend.routes import bp as api_bp
        app.register_blueprint(api_bp, url_prefix="/api")
        return "backend.routes:bp"
    except Exception as e1:
        # 2) Intentar una función de registro en routes_notes
        try:
            from backend.routes_notes import register_api
            register_api(app)
            return "backend.routes_notes:register_api"
        except Exception as e2:
            # 3) Fallback mínimo
            try:
                from backend.api import api as api_bp
                app.register_blueprint(api_bp, url_prefix="/api")
                return "backend.api:api"
            except Exception as e3:
                print("~ wsgi: no API registered:", e1, "|", e2, "|", e3)
                return None

api_src = _register_api(app)

# Health con marker para verificar qué wsgi está vivo
@app.get("/api/health")
def health():
    return jsonify(ok=True, note="wsgiapp", ver=VER, api=bool(api_src), api_src=api_src)

# Static mínimos
@app.get("/")
def static_root():
    try:
        return app.send_static_file("index.html")
    except Exception:
        return jsonify(ok=True, note="root")

@app.get("/ads.txt")
def static_ads():
    try:
        return app.send_static_file("ads.txt")
    except Exception:
        return ("", 204)

@app.get("/<path:filename>")
def static(filename):
    try:
        return send_from_directory(app.static_folder, filename)
    except Exception:
        return jsonify(error="static_not_found", file=filename), 404

# Auto create DB (idempotente)
try:
    if db is not None:
        with app.app_context():
            db.create_all()
            print("~ wsgi: Auto create DB OK")
except Exception as _e:
    print("~ wsgi: Auto create DB failed:", _e)
PY

############################################
# 3) Commit + push + verificación remota
############################################
git add -A
git commit -m "deploy: wsgi registers API (routes/routes_notes) with backend.api fallback; health marker; create_all()" || true
git push -u --force-with-lease origin "$BRANCH"

echo "[i] Esperando 15s a que Render redeploye…"
sleep 15

echo "[+] /api/health"
curl -i -s "${RENDER_URL}/api/health" | sed -n '1,80p'; echo
echo "[+] GET /api/notes"
curl -i -s "${RENDER_URL}/api/notes?page=1" | sed -n '1,120p'; echo
echo "[+] POST /api/notes"
curl -i -s -X POST -H "Content-Type: application/json" \
  -d '{"text":"remote-ok-v2","hours":24}' \
  "${RENDER_URL}/api/notes" | sed -n '1,160p'; echo
