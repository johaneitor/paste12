#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"
RENDER_URL="${RENDER_URL:-https://paste12-rmsk.onrender.com}"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"

echo "[+] Backups"
cp -f app.py "app.py.bak.$(date +%s)" 2>/dev/null || true
cp -f wsgi.py "wsgi.py.bak.$(date +%s)" 2>/dev/null || true
cp -f run.py  "run.py.bak.$(date +%s)" 2>/dev/null || true
cp -f backend/routes_notes.py "backend/routes_notes.py.bak.$(date +%s)" 2>/dev/null || true

# -------------------------------------------------------------------
# 1) backend/routes_notes.py: registrador de /api/notes idempotente
# -------------------------------------------------------------------
mkdir -p backend
cat > backend/routes_notes.py <<'PY'
from __future__ import annotations
import hashlib, os
from datetime import datetime, timedelta
from flask import Blueprint, jsonify, request

def _now(): 
    return datetime.utcnow()

def _fp(req) -> str:
    ip = req.headers.get("X-Forwarded-For","") or req.headers.get("CF-Connecting-IP","") or (req.remote_addr or "")
    ua = req.headers.get("User-Agent","")
    salt = os.environ.get("FP_SALT","")
    return hashlib.sha256(f"{ip}|{ua}|{salt}".encode()).hexdigest()[:32]

def _has_rule(app, rule: str, method: str) -> bool:
    try:
        for r in app.url_map.iter_rules():
            if str(r) == rule and method.upper() in r.methods:
                return True
    except Exception:
        pass
    return False

def register_api(app):
    """
    Registra /api/notes GET y POST si no existen aún. Idempotente.
    Requiere backend.models.Note y backend.db ya inicializados por create_app().
    """
    if _has_rule(app, "/api/notes", "GET") and _has_rule(app, "/api/notes", "POST"):
        return "present"

    from backend import db
    from backend.models import Note  # debe existir el modelo con author_fp

    api_bp = Blueprint("api_notes_capsule", __name__)

    @api_bp.get("/notes")
    def list_notes():
        page = max(1, int(request.args.get("page", 1) or 1))
        q = Note.query.order_by(Note.timestamp.desc())
        items = q.limit(20).offset((page-1)*20).all()
        now = _now()
        out = []
        for n in items:
            out.append({
                "id": n.id,
                "text": n.text,
                "timestamp": n.timestamp.isoformat(),
                "expires_at": n.expires_at.isoformat() if n.expires_at else None,
                "likes": n.likes,
                "views": n.views,
                "reports": n.reports,
                "author_fp": getattr(n, "author_fp", None),
                "now": now.isoformat(),
            })
        return jsonify(out), 200

    @api_bp.post("/notes")
    def create_note():
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
            text=text,
            timestamp=now,
            expires_at=now + timedelta(hours=hours),
            author_fp=_fp(request),
        )
        db.session.add(n)
        db.session.commit()
        return jsonify({
            "id": n.id,
            "text": n.text,
            "timestamp": n.timestamp.isoformat(),
            "expires_at": n.expires_at.isoformat() if n.expires_at else None,
            "likes": n.likes,
            "views": n.views,
            "reports": n.reports,
            "author_fp": getattr(n, "author_fp", None),
            "now": now.isoformat(),
        }), 201

    app.register_blueprint(api_bp, url_prefix="/api")
    return "registered"
PY

# -------------------------------------------------------------------
# 2) app.py: ÚNICA fuente de verdad de la app
# -------------------------------------------------------------------
cat > app.py <<'PY'
from __future__ import annotations
import os
from flask import Flask, jsonify
from backend import create_app, db

VER = "triplex-v1"

def _has_rule(app, rule: str, method: str) -> bool:
    try:
        for r in app.url_map.iter_rules():
            if str(r) == rule and method.upper() in r.methods:
                return True
    except Exception:
        pass
    return False

# Construimos la app mediante backend.create_app()
app: Flask = create_app()

# Si /api/notes no existe, registramos la cápsula
api_src = None
if not (_has_rule(app, "/api/notes", "GET") and _has_rule(app, "/api/notes", "POST")):
    try:
        from backend.routes_notes import register_api
        api_src = register_api(app)
    except Exception as _e:
        api_src = f"register_api_failed:{_e}"

# Health con marcador y fuente
if not _has_rule(app, "/api/health", "GET"):
    @app.get("/api/health")
    def _health():
        return jsonify(ok=True, note="triplex", ver=VER, api=_has_rule(app, "/api/notes", "GET"), api_src=api_src)

# Aseguramos create_all (SQLite u otro) — no falla si ya existe
try:
    with app.app_context():
        db.create_all()
except Exception as _e:
    pass

# Soporte para ejecutar localmente (python app.py)
if __name__ == "__main__":
    host = os.environ.get("HOST", "0.0.0.0")
    port = int(os.environ.get("PORT", "8000"))
    app.run(host=host, port=port)
PY

# -------------------------------------------------------------------
# 3) wsgi.py y run.py: apuntan a app:app
# -------------------------------------------------------------------
cat > wsgi.py <<'PY'
from app import app  # Render: gunicorn wsgi:app
PY

cat > run.py <<'PY'
from app import app

if __name__ == "__main__":
    import os
    host = os.environ.get("HOST", "0.0.0.0")
    port = int(os.environ.get("PORT", "8000"))
    app.run(host=host, port=port)
PY

echo "[+] Commit & push"
git add -A
git commit -m "triplex: unify entrypoints (app.py), wsgi/run proxy to app; register /api/notes if missing; health marker" || true
git push -u --force-with-lease origin "$BRANCH"

echo "[i] Hecho. Para probar remoto:"
echo "   curl -s ${RENDER_URL}/api/health | jq . || curl -s ${RENDER_URL}/api/health"
echo "   curl -i -s ${RENDER_URL}/api/notes?page=1 | sed -n '1,80p'"
echo "   curl -i -s -X POST -H 'Content-Type: application/json' -d '{\"text\":\"remote-triplex\",\"hours\":24}' ${RENDER_URL}/api/notes | sed -n '1,120p'"
