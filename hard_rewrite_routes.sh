#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
cd "$(dirname "$0")"
ts=$(date +%s)

# 1) Backup
cp -p backend/routes.py "backend/routes.py.bak.$ts" 2>/dev/null || true

# 2) Reescribe routes.py con una versión estable
cat > backend/routes.py <<'PY'
from flask import Blueprint, request, jsonify
from datetime import datetime, timezone, timedelta
from .models import Note
from . import db

bp = Blueprint("api", __name__, url_prefix="/api")

def _serialize(n: Note):
    now = datetime.now(timezone.utc)
    rem = max(0, int((n.expires_at - now).total_seconds()))
    return {
        "id": n.id,
        "text": n.text,
        "timestamp": n.timestamp.isoformat() if n.timestamp else None,
        "expires_at": n.expires_at.isoformat() if n.expires_at else None,
        "likes": getattr(n, "likes", 0) or 0,
        "views": getattr(n, "views", 0) or 0,
        "reports": getattr(n, "reports", 0) or 0,
        "remaining_seconds": rem,
    }

@bp.get("/notes")
def get_notes():
    page = max(int(request.args.get("page", 1) or 1), 1)
    per_page = min(int(request.args.get("per_page", 10) or 10), 50)
    now = datetime.now(timezone.utc)
    q = Note.query.filter(Note.expires_at > now).order_by(Note.timestamp.desc())
    p = q.paginate(page=page, per_page=per_page, error_out=False)
    return jsonify({
        "items": [_serialize(n) for n in p.items],
        "page": p.page, "pages": p.pages, "total": p.total
    })

@bp.post("/notes")
def create_note():
    data = request.get_json(silent=True) or {}
    text = (data.get("text") or "").strip()
    hours = int(data.get("hours") or 24*7)
    hours = max(1, min(hours, 24*30))
    if not text:
        return jsonify({"error": "Texto requerido"}), 400
    now = datetime.now(timezone.utc)
    n = Note(
        text=text,
        timestamp=now,
        expires_at=now + timedelta(hours=hours),
    )
    db.session.add(n)
    db.session.commit()
    return jsonify(_serialize(n)), 201

@bp.post("/notes/<int:note_id>/like")
def like_note(note_id: int):
    n = Note.query.get_or_404(note_id)
    n.likes = (getattr(n, "likes", 0) or 0) + 1
    db.session.commit()
    return jsonify({"likes": n.likes})

@bp.post("/notes/<int:note_id>/view")
def view_note(note_id: int):
    n = Note.query.get_or_404(note_id)
    n.views = (getattr(n, "views", 0) or 0) + 1
    db.session.commit()
    return jsonify({"views": n.views})

@bp.post("/notes/<int:note_id>/report")
def report_note(note_id: int):
    n = Note.query.get_or_404(note_id)
    n.reports = (getattr(n, "reports", 0) or 0) + 1
    deleted = False
    if n.reports >= 5:
        db.session.delete(n)
        deleted = True
    db.session.commit()
    return jsonify({"reports": 0 if deleted else n.reports, "deleted": deleted})
PY

# 3) Chequeo rápido: que la app importe y cree WSGI
python - <<'PY'
from backend import create_app
create_app()
print("✅ create_app() OK")
PY

# 4) Commit y push (forzará redeploy en Render)
git add backend/routes.py
git commit -m "fix(routes): reescritura limpia; eliminar bloque inválido e indentación rota" || true
git push -u origin "$(git rev-parse --abbrev-ref HEAD)"
