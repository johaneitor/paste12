#!/usr/bin/env bash
set -Eeuo pipefail

ts=$(date +%s)
echo "🔧 Hard reset backend/routes.py — $ts"

# 1) Backup
cp -p backend/routes.py "backend/routes.py.bak.$ts" 2>/dev/null || true

# 2) Reescribir routes.py completo (versión estable)
cat > backend/routes.py <<'PYCODE'
from __future__ import annotations

import os
from datetime import datetime, timezone, timedelta
from typing import Optional

from flask import Blueprint, current_app, jsonify, request
from sqlalchemy.exc import IntegrityError

from . import db, limiter
from .models import Note, LikeLog, ReportLog, ViewLog

# Blueprint único (se registra en create_app con url_prefix="/api")
bp = Blueprint("api", __name__)

# ===== Helpers =====
def _now() -> datetime:
    # Siempre consciente de zona horaria (UTC)
    return datetime.now(timezone.utc)

def _as_aware(dt: Optional[datetime]) -> Optional[datetime]:
    """Fuerza tz-aware en UTC si viene naive."""
    if dt is None:
        return None
    return dt if getattr(dt, "tzinfo", None) else dt.replace(tzinfo=timezone.utc)

def _fp() -> str:
    # prioridad: header -> cookie -> IP
    return (
        request.headers.get("X-Client-Fingerprint")
        or request.cookies.get("fp")
        or request.remote_addr
        or "anon"
    )

def _rate_key() -> str:
    return _fp()

def _per_page() -> int:
    # PAGE_SIZE clamped 10..100 (default 20)
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

# ===== Endpoints =====
@bp.get("/health")
def health():
    return jsonify({"ok": True, "now": _now().isoformat()}), 200

@bp.get("/notes")
def list_notes():
    now = _now()
    # página
    try:
        page = max(1, int(request.args.get("page", "1")))
    except Exception:
        page = 1
    page_size = _per_page()

    # ordenar por más nuevas y filtrar expiradas
    q = Note.query.filter(Note.expires_at > now).order_by(Note.timestamp.desc())
    items = q.offset((page - 1) * page_size).limit(page_size).all()
    has_more = len(items) == page_size

    return jsonify({
        "page": page,
        "page_size": page_size,
        "has_more": has_more,
        "notes": [_note_json(n, now) for n in items],
    })

# Crear nota — rate limit (1/10s y 500/día)
@bp.post("/notes")
@limiter.limit("1 per 10 seconds", key_func=_rate_key)
@limiter.limit("500 per day", key_func=_rate_key)
def create_note():
    now = _now()
    data = request.get_json(silent=True) or {}
    text = (data.get("text") or "").strip()
    if not text:
        return jsonify({"error": "text is required"}), 400

    try:
        hours = int(data.get("hours", 12))
    except Exception:
        hours = 12
    hours = max(1, min(hours, 24 * 7))  # 1..168

    n = Note(text=text, timestamp=now, expires_at=now + timedelta(hours=hours))
    db.session.add(n)
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
        return jsonify({"likes": int(n.likes or 0), "already_liked": False})
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
            # borrar la nota (cascade elimina logs)
            db.session.delete(n)
            db.session.commit()
            return jsonify({"deleted": True, "reports": 0, "already_reported": False})
        db.session.commit()
        return jsonify({"deleted": False, "reports": int(n.reports or 0), "already_reported": False})
    except IntegrityError:
        db.session.rollback()
        return jsonify({"deleted": False, "reports": int(n.reports or 0), "already_reported": True})
PYCODE

# 3) Validar sintaxis
python -m py_compile backend/routes.py && echo "✅ routes.py: sintaxis OK"

echo
echo "Ahora haz commit y push:"
echo "  git add backend/routes.py"
echo "  git commit -m 'reset(routes): versión estable con datetimes aware, paginación y logs idempotentes' || true"
echo "  git push -u origin main"
echo
echo "Luego redeploy y prueba:"
echo "  curl -sSf https://paste12-rmsk.onrender.com/api/health"
echo "  curl -sSf 'https://paste12-rmsk.onrender.com/api/notes?page=1' | head -c 400; echo"
