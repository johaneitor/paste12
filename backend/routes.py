from __future__ import annotations
# -*- coding: utf-8 -*-
from flask import Blueprint, request, jsonify, current_app
from hashlib import sha256
from datetime import datetime, timedelta
import sqlalchemy as sa

# Backend
from backend import db, limiter
from backend.models import Note, LikeLog, ReportLog, ViewLog
from flask import jsonify, current_app

# Blueprint sin prefix (el prefix /api lo pone create_app en backend/__init__.py)
bp = Blueprint('api', __name__)
# -------- utilidades --------
def _pick(*vals):
    for v in vals:
        if v is None:
            continue
        s = str(v).strip()
        if s:
            return s
    return ""

def _fp(req) -> str:
    uid = (req.cookies.get("uid") or "").strip()
    if len(uid) >= 8:
        base = f"uid:{uid}"
    else:
        ip = (req.headers.get("X-Forwarded-For") or req.remote_addr or "").split(",")[0].strip()
        ua = req.headers.get("User-Agent", "")
        base = f"{ip}|{ua}"
    return sha256(base.encode("utf-8")).hexdigest()

def _dto(n: Note) -> dict:
    return {
        "id": n.id,
        "text": getattr(n, "text", None),
        "timestamp": n.timestamp.isoformat() if getattr(n, "timestamp", None) else None,
        "expires_at": n.expires_at.isoformat() if getattr(n, "expires_at", None) else None,
        "likes": getattr(n, "likes", 0) or 0,
        "views": getattr(n, "views", 0) or 0,
        "reports": getattr(n, "reports", 0) or 0,
    }

# -------- health & routes --------
@bp.route("/health", methods=["GET"])
def health():
    return jsonify({"ok": True}), 200
@bp.route("/_routes", methods=["GET"])
def api_routes_dump():
    info = []
    for r in current_app.url_map.iter_rules():
        info.append({
            "rule": str(r),
            "methods": sorted(m for m in r.methods if m not in ("HEAD","OPTIONS")),
            "endpoint": r.endpoint,
        })
    info.sort(key=lambda x: x["rule"])
    return jsonify({"routes": info}), 200

# -------- CRUD --------
@limiter.limit("60/minute")
def get_note(note_id: int):
    n = db.session.get(Note, note_id)
    if not n:
        return jsonify({"error": "not_found"}), 404
    return jsonify(_dto(n)), 200

@limiter.limit("60/minute")
@bp.route('/api/notes/<int:note_id>/view', methods=['POST'])
def view_note(note_id: int):
    n = db.session.get(Note, note_id)
    if not n:
        return jsonify({"error": "not_found"}), 404
    fp = _fp(request)
    today = datetime.utcnow().date()
    already = db.session.query(ViewLog.id).filter_by(note_id=note_id, fingerprint=fp, view_date=today).first()
    if already:
        return jsonify({"ok": True, "views": n.views or 0, "already_viewed": True}), 200
    try:
        db.session.add(ViewLog(note_id=note_id, fingerprint=fp, view_date=today))
        n.views = (n.views or 0) + 1
        db.session.commit()
        return jsonify({"ok": True, "views": n.views}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": "view_failed", "detail": str(e)}), 500

@limiter.limit("60/minute")
@bp.route('/api/notes/<int:note_id>/like', methods=['POST'])
def like_note(note_id: int):
    n = db.session.get(Note, note_id)
    if not n:
        return jsonify({"error": "not_found"}), 404
    fp = _fp(request)
    already = db.session.query(LikeLog.id).filter_by(note_id=note_id, fingerprint=fp).first()
    if already:
        return jsonify({"ok": True, "likes": n.likes or 0, "already_liked": True}), 200
    try:
        db.session.add(LikeLog(note_id=note_id, fingerprint=fp))
        n.likes = (n.likes or 0) + 1
        db.session.commit()
        return jsonify({"ok": True, "likes": n.likes}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": "like_failed", "detail": str(e)}), 500

@limiter.limit("30/minute")
@bp.route('/api/notes/<int:note_id>/report', methods=['POST'])
def report_note(note_id: int):
    n = db.session.get(Note, note_id)
    if not n:
        return jsonify({"error": "not_found"}), 404
    fp = _fp(request)
    already = db.session.query(ReportLog.id).filter_by(note_id=note_id, fingerprint=fp).first()
    if already:
        return jsonify({"ok": True, "reports": n.reports or 0, "already_reported": True}), 200
    try:
        db.session.add(ReportLog(note_id=note_id, fingerprint=fp))
        n.reports = (n.reports or 0) + 1
        if (n.reports or 0) >= 5:
            db.session.delete(n)
            db.session.commit()
            return jsonify({"ok": True, "deleted": True, "reports": 5}), 200
        db.session.commit()
        return jsonify({"ok": True, "reports": n.reports}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": "report_failed", "detail": str(e)}), 500
def api_ping():
    return jsonify({"pong": True}), 200
@bp.route("/routes", methods=["GET"])
def api_routes_dump_alias():
    return api_routes_dump()
@api.record_once
def _ensure_ping_route(state):
    app = state.app
    try:
        # si ya existe alguna regla que termine exactamente en /api/ping, no hacemos nada
        for r in app.url_map.iter_rules():
            if str(r).rstrip("/") == "/api/ping":
                break
        else:
            app.add_url_rule(
                "/api/ping", endpoint="api_ping_direct",
                view_func=(lambda: jsonify({"ok": True, "pong": True})), methods=["GET"]
            )
    except Exception:
        # no rompemos el registro del blueprint
        pass


import backend.routes_notes  # registra /api/notes (capsulado)
