from __future__ import annotations
from flask import Blueprint, request, jsonify, current_app, Response
from sqlalchemy import desc
from typing import List
from . import db
from .models import Note

bp = Blueprint("api", __name__, url_prefix="/api")

def _as_json(obj, status=200, headers: dict | None = None):
    from flask import json
    r = current_app.response_class(
        response=json.dumps(obj, ensure_ascii=False),
        status=status,
        mimetype="application/json",
    )
    if headers:
        for k,v in headers.items():
            r.headers[k] = v
    # CORS headers consistentes
    r.headers.setdefault("Access-Control-Allow-Origin", "*")
    r.headers.setdefault("Access-Control-Allow-Methods", "GET, POST, HEAD, OPTIONS")
    r.headers.setdefault("Access-Control-Allow-Headers", "Content-Type")
    r.headers.setdefault("Access-Control-Max-Age", "86400")
    return r

@bp.route("/notes", methods=["OPTIONS"])
def notes_options():
    return _as_json("", status=204)

@bp.route("/notes", methods=["GET"])
def list_notes():
    # Paginación por before_id y limit (como venías testeando)
    try:
        limit = max(1, min(int(request.args.get("limit", "10")), 50))
    except Exception:
        limit = 10
    before_id = request.args.get("before_id")
    q = Note.query
    if before_id and before_id.isdigit():
        q = q.filter(Note.id < int(before_id))
    q = q.order_by(desc(Note.timestamp)).limit(limit)
    rows: List[Note] = q.all()
    body = [n.to_dict() for n in rows]

    # Link: next si hay más
    next_link = None
    if rows:
        last_id = rows[-1].id
        # ¿quedan más? comprobación rápida
        more = Note.query.filter(Note.id < last_id).order_by(desc(Note.timestamp)).first()
        if more:
            base = request.url_root.rstrip("/")
            next_link = f'<{base}/api/notes?limit={limit}&before_id={last_id}>; rel="next"'

    headers = {}
    if next_link:
        headers["Link"] = next_link

    return _as_json(body, 200, headers)

@bp.route("/notes", methods=["POST"])
def create_note():
    data = request.get_json(silent=True) or {}
    text = (data.get("text") if isinstance(data, dict) else None) or request.form.get("text") or ""
    text = text.strip()
    if not text:
        return _as_json({"error": "text requerido"}, 400)
    n = Note(text=text, expires_at=Note.compute_expiry())
    db.session.add(n)
    db.session.commit()
    return _as_json(n.to_dict(), 201)

def _act_on_note(note_id: int, field: str) -> Response:
    n = Note.query.get(note_id)
    if not n:
        return _as_json({"error": "not found"}, 404)
    setattr(n, field, int(getattr(n, field) or 0) + 1)
    db.session.commit()
    return _as_json({"ok": True, "id": n.id, field: getattr(n, field)})

@bp.route("/notes/<int:note_id>/like", methods=["POST"])
def like_note(note_id: int): return _act_on_note(note_id, "likes")

@bp.route("/notes/<int:note_id>/view", methods=["POST"])
def view_note(note_id: int): return _act_on_note(note_id, "views")

@bp.route("/notes/<int:note_id>/report", methods=["POST"])
def report_note(note_id: int): return _act_on_note(note_id, "reports")
