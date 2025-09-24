#!/usr/bin/env bash
set -euo pipefail
mkdir -p backend/modules
cat > backend/modules/interactions.py <<'PY'
from __future__ import annotations
import os, hashlib
from datetime import datetime, timedelta
from typing import Optional, Tuple

from flask import Blueprint, jsonify, request
from sqlalchemy import text
from werkzeug.exceptions import NotFound, BadRequest

# Intentamos usar tu app/ORM reales
try:
    from backend import db
    from backend.models import Note
except Exception as _e:
    db = None
    Note = None

interactions_bp = Blueprint("interactions", __name__)

# === Helpers ===
def _now() -> datetime:
    return datetime.utcnow()

def _fp() -> str:
    ip = request.headers.get("X-Forwarded-For","") or request.headers.get("CF-Connecting-IP","") or (request.remote_addr or "")
    ua = request.headers.get("User-Agent","")
    salt = os.environ.get("FP_SALT","")
    try:
        return hashlib.sha256(f"{ip}|{ua}|{salt}".encode()).hexdigest()[:32]
    except Exception:
        return "noctx"

def _get_note_or_404(note_id: int):
    if Note is None or db is None:
        raise RuntimeError("DB/Note no disponibles en interactions module")
    obj = Note.query.get(note_id)
    if obj is None:
        raise NotFound("note not found")
    return obj

def _ensure_sa():
    if db is None:
        raise RuntimeError("SQLAlchemy no disponible")

# === Endpoints ===

@interactions_bp.post("/notes/<int:note_id>/like")
def like_note(note_id: int):
    """
    Idempotente: si (actor_fp, note_id) ya existe en like_log, NO duplica.
    Incrementa note.likes sólo en el primer like.
    """
    _ensure_sa()
    n = _get_note_or_404(note_id)
    actor = _fp()
    try:
        # intentamos insertar el evento
        ins = db.session.execute(
            text("INSERT INTO like_log(note_id, actor_fp) VALUES(:n,:fp)"),
            {"n": note_id, "fp": actor},
        )
        # si insertó, sumamos +1
        if ins.rowcount:
            db.session.execute(
                text("UPDATE note SET likes = likes + 1 WHERE id=:n"),
                {"n": note_id},
            )
        db.session.commit()
        return jsonify(ok=True, note_id=note_id, liked=True, likes=int(n.likes + (1 if ins.rowcount else 0)))
    except Exception as e:
        db.session.rollback()
        # Unique violation → ya estaba likeado → idempotente
        msg = str(e)
        if "UNIQUE" in msg or "duplicate key" in msg:
            return jsonify(ok=True, note_id=note_id, liked=True, likes=int(n.likes)), 200
        return jsonify(ok=False, error="like_failed", detail=msg), 500

@interactions_bp.post("/notes/<int:note_id>/view")
def view_note(note_id: int):
    """
    Cuenta una vista por (actor_fp, note_id) por ventana de 15 minutos.
    Si insertó, incrementa views.
    """
    _ensure_sa()
    _ = _get_note_or_404(note_id)
    actor = _fp()
    now = _now()
    # bucket 15m
    bucket = now.replace(minute=(now.minute // 15) * 15, second=0, microsecond=0)
    try:
        inserted = db.session.execute(
            text("""
                INSERT INTO view_log(note_id, actor_fp, seen_at)
                SELECT :n, :fp, CURRENT_TIMESTAMP
                WHERE NOT EXISTS (
                  SELECT 1 FROM view_log
                  WHERE note_id = :n
                    AND actor_fp = :fp
                    AND seen_at >= :bucket
                )
            """),
            {"n": note_id, "fp": actor, "bucket": bucket},
        )
        if inserted.rowcount:
            db.session.execute(
                text("UPDATE note SET views = views + 1 WHERE id=:n"),
                {"n": note_id},
            )
            db.session.commit()
            return jsonify(ok=True, note_id=note_id, viewed=True)
        else:
            db.session.commit()
            return jsonify(ok=True, note_id=note_id, viewed=False, reason="window"), 200
    except Exception as e:
        db.session.rollback()
        return jsonify(ok=False, error="view_failed", detail=str(e)), 500

@interactions_bp.get("/notes/<int:note_id>/stats")
def note_stats(note_id: int):
    _ensure_sa()
    n = _get_note_or_404(note_id)
    return jsonify(ok=True, note_id=note_id, likes=int(n.likes), views=int(n.views))
PY
