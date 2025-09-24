#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"
RENDER_URL="${RENDER_URL:-https://paste12-rmsk.onrender.com}"

echo "[+] Backup previo de wsgiapp.py (si existe)"
[ -f wsgiapp.py ] && cp -f wsgiapp.py "wsgiapp.py.bak.$(date +%s)" || true

echo "[+] Escribiendo wsgiapp.py con fallback /api/notes"
cat > wsgiapp.py <<'PY'
from __future__ import annotations
import os
from datetime import datetime, timedelta
from flask import Blueprint, jsonify, request
from backend import create_app, db
from backend.models import Note

# --- helpers mínimos ---
def _now():
    return datetime.utcnow()

def _fp() -> str:
    ip = request.headers.get("X-Forwarded-For","") or request.headers.get("CF-Connecting-IP","") or (request.remote_addr or "")
    ua = request.headers.get("User-Agent","")
    salt = os.environ.get("FP_SALT","")
    try:
        import hashlib
        return hashlib.sha256(f"{ip}|{ua}|{salt}".encode()).hexdigest()[:32]
    except Exception:
        return "noctx"

def _has_rule(app, rule: str, method: str) -> bool:
    try:
        for r in app.url_map.iter_rules():
            if str(r) == rule and method.upper() in r.methods:
                return True
    except Exception:
        pass
    return False

def _note_json(n: Note, now: datetime | None = None) -> dict:
    now = now or _now()
    return {
        "id": n.id,
        "text": n.text,
        "timestamp": (n.timestamp.isoformat() if getattr(n, "timestamp", None) else None),
        "expires_at": (n.expires_at.isoformat() if getattr(n, "expires_at", None) else None),
        "likes": getattr(n, "likes", 0),
        "views": getattr(n, "views", 0),
        "reports": getattr(n, "reports", 0),
        "author_fp": getattr(n, "author_fp", None),
        "now": now.isoformat(),
    }

# --- app base desde tu factory ---
app = create_app()

# --- fallback: si /api/notes no existe, inyectar blueprint alternativo ---
if not (_has_rule(app, "/api/notes", "GET") and _has_rule(app, "/api/notes", "POST")):
    bp_fallback = Blueprint("api_fallback_notes", __name__)

    @bp_fallback.get("/notes")
    def list_notes():
        try:
            page = 1
            try:
                page = max(1, int(request.args.get("page", 1)))
            except Exception:
                pass
            q = Note.query.order_by(Note.timestamp.desc())
            items = q.limit(20).offset((page-1)*20).all()
            return jsonify([_note_json(n) for n in items]), 200
        except Exception as e:
            return jsonify(ok=False, error="list_failed", detail=str(e)), 500

    @bp_fallback.post("/notes")
    def create_note():
        try:
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
                author_fp=_fp(),
            )
            db.session.add(n)
            db.session.commit()
            return jsonify(_note_json(n, now)), 201
        except Exception as e:
            db.session.rollback()
            return jsonify(ok=False, error="create_failed", detail=str(e)), 500

    try:
        app.register_blueprint(bp_fallback, url_prefix="/api")
    except Exception:
        # Si fallara por cualquier razón, lo dejamos como estaba.
        pass

# --- asegurar tablas (no falla si ya existen) ---
try:
    with app.app_context():
        db.create_all()
except Exception:
    pass
PY

echo "[+] Commit & push"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
git add -A
git commit -m "wsgiapp: inject fallback /api/notes blueprint if missing; keep existing app intact" || true
git push -u --force-with-lease origin "$BRANCH"

echo "[i] Esperando 15s a que Render redeploye…"
sleep 15

echo "[+] Verificando remoto:"
echo " - /api/health"
curl -s "$RENDER_URL/api/health" || true
echo
echo " - GET /api/notes"
curl -i -s "$RENDER_URL/api/notes?page=1" | sed -n '1,80p'
echo
echo " - POST /api/notes"
curl -i -s -X POST -H "Content-Type: application/json" \
  -d '{"text":"remote-fallback","hours":24}' \
  "$RENDER_URL/api/notes" | sed -n '1,120p'
echo
