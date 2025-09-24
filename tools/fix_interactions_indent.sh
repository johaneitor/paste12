#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"

mkdir -p backend/modules

echo "[+] Escribiendo backend/modules/interactions.py (limpio y con indentación correcta)…"
cat > backend/modules/interactions.py <<'PY'
from __future__ import annotations
import os, math, hashlib
from datetime import datetime, timezone
from typing import Optional
from flask import Blueprint, jsonify, request, current_app
from sqlalchemy import UniqueConstraint, Index, func

# Intentar usar ORM real del proyecto
db = None
Note = None
try:
    from backend import db as _db
    from backend.models import Note as _Note
    db, Note = _db, _Note
except Exception:
    # Fallback mínimo si se usa este módulo suelto
    from flask_sqlalchemy import SQLAlchemy
    from flask import Flask
    _app = current_app._get_current_object() if current_app else None
    if _app is None:
        _app = Flask(__name__)
        _app.config["SQLALCHEMY_DATABASE_URI"] = os.environ.get("DATABASE_URL","sqlite:///app.db")
        _app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    db = SQLAlchemy(_app)

    class Note(db.Model):  # type: ignore
        __tablename__ = "note"
        id = db.Column(db.Integer, primary_key=True)
        text = db.Column(db.Text, nullable=False)
        timestamp = db.Column(db.DateTime, nullable=False, index=True)
        expires_at = db.Column(db.DateTime, nullable=False, index=True)
        likes = db.Column(db.Integer, default=0, nullable=False)
        views = db.Column(db.Integer, default=0, nullable=False)
        reports = db.Column(db.Integer, default=0, nullable=False)
        author_fp = db.Column(db.String(64), nullable=False, default="noctx", index=True)

def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)

def _fp() -> str:
    ip = request.headers.get("X-Forwarded-For","") or request.headers.get("CF-Connecting-IP","") or (request.remote_addr or "")
    ua = request.headers.get("User-Agent","")
    salt = os.environ.get("FP_SALT","")
    try:
        return hashlib.sha256(f"{ip}|{ua}|{salt}".encode()).hexdigest()[:32]
    except Exception:
        return "noctx"

# === Modelo de eventos (sin unlike). Idempotencia por constraints ===
class InteractionEvent(db.Model):  # type: ignore
    __tablename__ = "interaction_event"
    id = db.Column(db.Integer, primary_key=True)
    note_id = db.Column(db.Integer, db.ForeignKey("note.id", ondelete="CASCADE"), nullable=False, index=True)
    fp = db.Column(db.String(64), nullable=False, index=True)
    # 'like' | 'view'
    type = db.Column(db.String(16), nullable=False, index=True)
    # bucket_15m: ventana de 15 minutos (views); para like queda 0
    bucket_15m = db.Column(db.Integer, nullable=False, default=0, index=True)
    created_at = db.Column(db.DateTime, nullable=False, default=_utcnow, index=True)

    __table_args__ = (
        # Un like por usuario por nota (idempotente)
        UniqueConstraint('note_id', 'fp', 'type',
                         name='uq_like_per_user',
                         deferrable=True, initially='DEFERRED'),
        # Una view por usuario por nota por bucket de 15 min (idempotente x ventana)
        UniqueConstraint('note_id', 'fp', 'type', 'bucket_15m',
                         name='uq_view_15m_per_user',
                         deferrable=True, initially='DEFERRED'),
        Index('ix_evt_note_type_bucket', 'note_id', 'type', 'bucket_15m'),
    )

bp = Blueprint("interactions", __name__)

def _bucket_15m(ts: Optional[datetime] = None) -> int:
    ts = ts or _utcnow()
    epoch = ts.timestamp()  # seconds
    return int(epoch // 900)

def _note_or_404(note_id: int) -> Optional[Note]:
    n = Note.query.filter_by(id=note_id).first()
    return n

@bp.post("/notes/<int:note_id>/like")
def like_note(note_id: int):
    n = _note_or_404(note_id)
    if not n:
        return jsonify(ok=False, error="not_found"), 404
    fp = _fp()
    try:
        evt = InteractionEvent(note_id=note_id, fp=fp, type="like", bucket_15m=0)
        db.session.add(evt)
        db.session.commit()
    except Exception:
        db.session.rollback()
    likes = db.session.query(func.count(InteractionEvent.id)).filter_by(note_id=note_id, type="like").scalar() or 0
    n.likes = int(likes)
    db.session.commit()
    return jsonify(ok=True, id=note_id, likes=n.likes), 200

@bp.post("/notes/<int:note_id>/view")
def view_note(note_id: int):
    n = _note_or_404(note_id)
    if not n:
        return jsonify(ok=False, error="not_found"), 404
    fp = _fp()
    b = _bucket_15m()
    try:
        evt = InteractionEvent(note_id=note_id, fp=fp, type="view", bucket_15m=b)
        db.session.add(evt)
        db.session.commit()
    except Exception:
        db.session.rollback()
    views = db.session.query(func.count(InteractionEvent.id)).filter_by(note_id=note_id, type="view").scalar() or 0
    n.views = int(views)
    db.session.commit()
    return jsonify(ok=True, id=note_id, views=n.views, window="15m"), 200

@bp.get("/notes/<int:note_id>/stats")
def stats_note(note_id: int):
    n = _note_or_404(note_id)
    if not n:
        return jsonify(ok=False, error="not_found"), 404
    likes = db.session.query(func.count(InteractionEvent.id)).filter_by(note_id=note_id, type="like").scalar() or 0
    views = db.session.query(func.count(InteractionEvent.id)).filter_by(note_id=note_id, type="view").scalar() or 0
    return jsonify(ok=True, id=note_id, likes=int(likes), views=int(views),
                   denorm={"likes": n.likes, "views": n.views}), 200

def ensure_schema():
    try:
        db.create_all()
    except Exception:
        pass

def register_into(app):
    try:
        app.register_blueprint(bp, url_prefix="/api")
    except Exception:
        pass
    with app.app_context():
        ensure_schema()

# --- Alias blueprint para rutas “seguras” (/api/ix/...) ---
alias_bp = Blueprint("interactions_alias", __name__)

@alias_bp.post("/ix/notes/<int:note_id>/like")
def _alias_like(note_id:int):
    return like_note(note_id)

@alias_bp.post("/ix/notes/<int:note_id>/view")
def _alias_view(note_id:int):
    return view_note(note_id)

@alias_bp.get("/ix/notes/<int:note_id>/stats")
def _alias_stats(note_id:int):
    return stats_note(note_id)

def register_alias_into(app):
    try:
        app.register_blueprint(alias_bp, url_prefix="/api")
    except Exception:
        pass

# === Diag: existencia de tabla y counts básicos ===
@bp.get("/notes/diag", endpoint="interactions_diag")
def interactions_diag():
    try:
        likes_cnt = db.session.query(func.count(InteractionEvent.id)).filter_by(type="like").scalar() or 0
        views_cnt = db.session.query(func.count(InteractionEvent.id)).filter_by(type="view").scalar() or 0
        # listar tablas disponible vía inspector puede variar entre SA1/SA2, mantener simple:
        return jsonify(ok=True, has_interaction_event=True,
                       total_likes=int(likes_cnt), total_views=int(views_cnt)), 200
    except Exception as e:
        return jsonify(ok=False, error="diag_failed", detail=str(e)), 500

# Auto-registro suave si hay app activa
try:
    _app = current_app._get_current_object()
    if _app:
        register_into(_app)
        register_alias_into(_app)
except Exception:
    pass
PY

echo "[+] Commit & push"
git add -A
git commit -m "fix(interactions): rewrite clean module, correct indentation, ensure schema + alias /api/ix" || true
git push -u --force-with-lease origin "$(git rev-parse --abbrev-ref HEAD)"

cat <<'NEXT'

[•] Hecho. Ahora:
1) Esperá a que Render redeploye.
2) Verifica:
   curl -s https://paste12-rmsk.onrender.com/api/diag/import | jq .
   curl -s https://paste12-rmsk.onrender.com/api/debug-urlmap | jq '.rules | map(select(.rule|test("^/api/(notes|ix)/")))'
   curl -s https://paste12-rmsk.onrender.com/api/notes/diag | jq .

3) Prueba interacciones (reemplaza $ID por uno real):
   ID=$(curl -s 'https://paste12-rmsk.onrender.com/api/notes?page=1' | jq -r '.[0].id')
   curl -i -s -X POST "https://paste12-rmsk.onrender.com/api/ix/notes/$ID/like"  | sed -n '1,120p'
   curl -i -s -X POST "https://paste12-rmsk.onrender.com/api/ix/notes/$ID/view"  | sed -n '1,120p'
   curl -i -s      "https://paste12-rmsk.onrender.com/api/ix/notes/$ID/stats"    | sed -n '1,160p'

Si /api/diag/import muestra "import_path: render_entry:app", ya quedó cargado el entrypoint correcto.
NEXT
