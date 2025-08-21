#!/usr/bin/env bash
set -Eeuo pipefail

echo "⚠️  Esto VA A BORRAR todas las notas/likes/vistas/reportes. Escribe YES para continuar."
read -r ans
[[ "$ans" == "YES" ]] || { echo "Abortado."; exit 1; }

ts=$(date +%s)
root="$(pwd)"
inst="$root/instance"
dbfile="$inst/production.db"
bak="backups_$ts"
mkdir -p "$bak" "$inst"

echo "🗄️  Backup a $bak/"
cp -av backend/models.py "$bak/models.py" 2>/dev/null || true
cp -av backend/routes.py "$bak/routes.py" 2>/dev/null || true
[[ -f "$dbfile" ]] && cp -av "$dbfile" "$bak/production.db"

echo "🧱 Escribiendo backend/models.py…"
cat > backend/models.py <<'PY'
from __future__ import annotations
from datetime import datetime, timezone, date
from . import db

def _utcnow():
    return datetime.now(timezone.utc)

class Note(db.Model):
    __tablename__ = "note"
    id = db.Column(db.Integer, primary_key=True)
    text = db.Column(db.Text, nullable=False)
    timestamp = db.Column(db.DateTime(timezone=True), default=_utcnow, nullable=False, index=True)
    expires_at = db.Column(db.DateTime(timezone=True), nullable=False, index=True)
    likes = db.Column(db.Integer, nullable=False, default=0)
    views = db.Column(db.Integer, nullable=False, default=0)
    reports = db.Column(db.Integer, nullable=False, default=0)
    author_fp = db.Column(db.String(128), nullable=False, index=True, default="anon")

class LikeLog(db.Model):
    __tablename__ = "like_log"
    id = db.Column(db.Integer, primary_key=True)
    note_id = db.Column(db.Integer, db.ForeignKey("note.id", ondelete="CASCADE"), nullable=False, index=True)
    fingerprint = db.Column(db.String(128), nullable=False)
    created_at = db.Column(db.DateTime(timezone=True), default=_utcnow, nullable=False)
    __table_args__ = (db.UniqueConstraint("note_id", "fingerprint", name="uq_like_note_fp"),)

class ReportLog(db.Model):
    __tablename__ = "report_log"
    id = db.Column(db.Integer, primary_key=True)
    note_id = db.Column(db.Integer, db.ForeignKey("note.id", ondelete="CASCADE"), nullable=False, index=True)
    fingerprint = db.Column(db.String(128), nullable=False)
    created_at = db.Column(db.DateTime(timezone=True), default=_utcnow, nullable=False)
    __table_args__ = (db.UniqueConstraint("note_id", "fingerprint", name="uq_report_note_fp"),)

class ViewLog(db.Model):
    __tablename__ = "view_log"
    id = db.Column(db.Integer, primary_key=True)
    note_id = db.Column(db.Integer, db.ForeignKey("note.id", ondelete="CASCADE"), nullable=False, index=True)
    fingerprint = db.Column(db.String(128), nullable=False, index=True)
    view_date = db.Column(db.Date, nullable=False, index=True)  # 1 vista/día/nota/fp
    created_at = db.Column(db.DateTime(timezone=True), default=_utcnow, nullable=False, index=True)
    __table_args__ = (db.UniqueConstraint("note_id", "fingerprint", "view_date", name="uq_view_note_fp_day"),)
PY

echo "🧭 Escribiendo backend/routes.py…"
cat > backend/routes.py <<'PY'
from __future__ import annotations
import os
from datetime import datetime, timezone, timedelta
from typing import Optional
from flask import Blueprint, request, jsonify, abort
from sqlalchemy.exc import IntegrityError
from sqlalchemy import func
from . import db, limiter
from .models import Note, LikeLog, ReportLog, ViewLog

bp = Blueprint("api", __name__)  # __init__ lo registra con url_prefix='/api'

def _now() -> datetime:
    return datetime.now(timezone.utc)

def _as_aware(dt: Optional[datetime]) -> Optional[datetime]:
    if dt is None: return None
    return dt if getattr(dt, "tzinfo", None) else dt.replace(tzinfo=timezone.utc)

def _fp() -> str:
    h = request.headers
    return (
        h.get("X-Client-Fingerprint")
        or h.get("X-User-Token")
        or request.cookies.get("p12_fp")
        or h.get("CF-Connecting-IP")
        or (h.get("X-Forwarded-For","").split(",")[0].strip() if h.get("X-Forwarded-For") else None)
        or request.cookies.get("fp")
        or request.remote_addr
        or "anon"
    )

def _rate_key():  # usado por Flask-Limiter
    return _fp()

def _page_size() -> int:
    try:
        v = int(os.getenv("PAGE_SIZE", "20"))
    except Exception:
        v = 20
    return max(10, min(v, 100))

def _note_json(n: Note, now: Optional[datetime] = None) -> dict:
    now = _as_aware(now) or _now()
    ts = _as_aware(getattr(n, "timestamp", None))
    exp = _as_aware(getattr(n, "expires_at", None))
    remaining = max(0, int((exp - now).total_seconds())) if exp else None
    return {
        "id": n.id,
        "text": n.text,
        "timestamp": ts.isoformat() if ts else None,
        "expires_at": exp.isoformat() if exp else None,
        "remaining": remaining,
        "likes": int(n.likes or 0),
        "views": int(n.views or 0),
        "reports": int(n.reports or 0),
    }

@bp.get("/health")
def health():
    return jsonify({"ok": True, "now": _now().isoformat()}), 200

@bp.get("/notes")
def list_notes():
    now = _now()
    try:
        page = max(1, int(request.args.get("page", "1")))
    except Exception:
        page = 1
    size = _page_size()
    q = Note.query.filter(Note.expires_at > now).order_by(Note.timestamp.desc())
    items = q.offset((page - 1) * size).limit(size).all()
    has_more = len(items) == size
    return jsonify({
        "page": page,
        "page_size": size,
        "has_more": has_more,
        "notes": [_note_json(n, now) for n in items],
    })

@bp.post("/notes")
@limiter.limit("1 per 10 seconds", key_func=_rate_key)
@limiter.limit("500 per day", key_func=_rate_key)
def create_note():
    data = request.get_json(silent=True) or {}
    text = (data.get("text") or "").strip()
    if not text:
        return jsonify({"error": "text is required"}), 400

    fp = _fp()
    now = _now()
    # límite por usuario por día (server-side)
    try:
        max_day = int(os.getenv("NOTES_PER_DAY", "10"))
    except Exception:
        max_day = 10
    start_day = now.replace(hour=0, minute=0, second=0, microsecond=0)
    count_today = db.session.query(func.count(Note.id)).filter(
        Note.author_fp == fp, Note.timestamp >= start_day
    ).scalar() or 0
    if count_today >= max_day:
        return jsonify({"error": "daily limit reached", "limit": max_day}), 429

    # TTL
    try:
        hours = int(data.get("hours", 12))
    except Exception:
        hours = 12
    hours = max(1, min(hours, 24 * 7))  # 1..168

    n = Note(
        text=text,
        timestamp=now,
        expires_at=now + timedelta(hours=hours),
        author_fp=fp,
    )
    db.session.add(n)
    db.session.flush()  # obtener id

    # cap global
    try:
        max_notes = int(os.getenv("MAX_NOTES", "12000"))
    except Exception:
        max_notes = 12000
    total = db.session.query(func.count(Note.id)).scalar() or 0
    if total > max_notes:
        excess = total - max_notes
        olds = Note.query.order_by(Note.timestamp.asc()).limit(excess).all()
        for o in olds:
            db.session.delete(o)

    db.session.commit()
    return jsonify(_note_json(n, now)), 201

@bp.post("/notes/<int:note_id>/like")
def like_note(note_id: int):
    n = Note.query.get_or_404(note_id)
    fp = _fp()
    try:
        db.session.add(LikeLog(note_id=note_id, fingerprint=fp))
        db.session.flush()
        n.likes = int(n.likes or 0) + 1
        db.session.commit()
        return jsonify({"likes": n.likes, "already_liked": False})
    except IntegrityError:
        db.session.rollback()
        return jsonify({"likes": int(n.likes or 0), "already_liked": True})

@bp.post("/notes/<int:note_id>/view")
def view_note(note_id: int):
    n = Note.query.get_or_404(note_id)
    fp = _fp()
    today = _now().date()
    counted = False
    try:
        db.session.add(ViewLog(note_id=note_id, fingerprint=fp, view_date=today))
        db.session.flush()
        n.views = int(n.views or 0) + 1
        db.session.commit()
        counted = True
    except IntegrityError:
        db.session.rollback()
    return jsonify({"views": int(n.views or 0), "counted": counted})

@bp.post("/notes/<int:note_id>/report")
def report_note(note_id: int):
    n = Note.query.get_or_404(note_id)
    fp = _fp()
    try:
        db.session.add(ReportLog(note_id=note_id, fingerprint=fp))
        db.session.flush()
        n.reports = int(n.reports or 0) + 1
        if n.reports >= 5:
            db.session.delete(n)  # cascada borra logs
            db.session.commit()
            return jsonify({"deleted": True, "reports": 0, "already_reported": False})
        db.session.commit()
        return jsonify({"deleted": False, "reports": n.reports, "already_reported": False})
    except IntegrityError:
        db.session.rollback()
        return jsonify({"deleted": False, "reports": int(n.reports or 0), "already_reported": True})
PY

echo "🧹 Drop & Create de la DB…"
python - <<'PY'
import sys, os
sys.path.insert(0, os.getcwd())
from backend import create_app, db
from sqlalchemy import text
app = create_app()
with app.app_context():
    db.drop_all()
    db.create_all()
    # índices útiles (idempotentes por si repites)
    with db.engine.begin() as conn:
        conn.execute(text("CREATE INDEX IF NOT EXISTS ix_note_ts_desc ON note (timestamp DESC)"))
        conn.execute(text("CREATE INDEX IF NOT EXISTS ix_note_exp_ts ON note (expires_at, timestamp)"))
print("✓ DB recreada.")
PY

echo
echo "✅ Listo. Variables de entorno sugeridas en Render:"
echo "  MAX_NOTES=12000"
echo "  NOTES_PER_DAY=10"
echo "  PAGE_SIZE=20"
echo "  MAX_PAGE_SIZE=100"
echo "  RATELIMIT_STORAGE_URL=memory://   # (ideal: Redis si lo habilitas)"
echo
echo "Luego: git add backend/models.py backend/routes.py"
echo "      git commit -m 'reset(aggressive): schema limpio + límites (12k y 10/día)' || true"
echo "      git push -u origin main"
echo
echo "Smoke test:"
echo "  curl -sSf https://paste12-rmsk.onrender.com/api/health"
echo "  curl -sSf 'https://paste12-rmsk.onrender.com/api/notes?page=1' | head -c 400; echo"
