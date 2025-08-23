from __future__ import annotations
from flask import Blueprint, request, jsonify, send_from_directory
from hashlib import sha256
import os
from datetime import datetime, timedelta, date
from pathlib import Path

from backend import db, limiter
from backend.models import Note, ReportLog, LikeLog, ViewLog

api = Blueprint("api", __name__, url_prefix="/api")

def _fingerprint_from_request(req):
    uid = req.cookies.get('uid')
    if uid and len(uid) >= 8:
        base = f"uid:{uid}"
    else:
        ip = (req.headers.get("X-Forwarded-For") or getattr(req, "remote_addr", "") or "").split(",")[0].strip()
        ua = req.headers.get("User-Agent", "")
        base = f"{ip}|{ua}"
    return sha256(base.encode("utf-8")).hexdigest()

def _to_dict(n: Note):
    return {
        "id": n.id,
        "text": n.text,
        "timestamp": n.timestamp.isoformat() if getattr(n, "timestamp", None) else None,
        "expires_at": n.expires_at.isoformat() if getattr(n, "expires_at", None) else None,
        "likes": getattr(n, "likes", 0) or 0,
        "views": getattr(n, "views", 0) or 0,
        "reports": getattr(n, "reports", 0) or 0,
    }

@api.route("/health", methods=["GET"])
def health():
    return jsonify({"ok": True}), 200


@api.route("/notes", methods=["POST"])
def create_note():
    raw_json = request.get_json(silent=True) or {}
    data = raw_json if isinstance(raw_json, dict) else {}

    def pick(*vals):
        for v in vals:
            if v is not None and str(v).strip() != "":
                return str(v)
        return ""

    text = pick(
        data.get("text") if isinstance(data, dict) else None,
        request.form.get("text"),
        request.values.get("text"),
    ).strip()

    hours_raw = pick(
        (data.get("hours") if isinstance(data, dict) else None),
        request.form.get("hours"),
        request.values.get("hours"),
        "24",
    )
    try:
        hours = int(hours_raw)
    except Exception:
        hours = 24

    if not text:
        return jsonify({"error": "text_required"}), 400

    hours = max(1, min(hours, 720))
    now = datetime.utcnow()
    try:
        n = Note(
            text=text,
            timestamp=now,
            expires_at=now + timedelta(hours=hours),
            author_fp=_fingerprint_from_request(request),
        )
        db.session.add(n)
        db.session.commit()
        return jsonify({"id": n.id, "ok": True}), 201
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": "create_failed", "detail": str(e)}), 500

@api.route("/notes/<int:note_id>", methods=["GET"])
def get_note(note_id: int):
    n = db.session.get(Note, note_id)
    if not n:
        return jsonify({"error": "not_found"}), 404
    return jsonify(_to_dict(n)), 200

@limiter.limit("30/minute")
@api.route("/notes/<int:note_id>/like", methods=["POST"])
def like_note(note_id: int):
    n = db.session.get(Note, note_id)
    if not n:
        return jsonify({"error": "not_found"}), 404
    fp = _fingerprint_from_request(request)
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
@api.route("/notes/<int:note_id>/view", methods=["POST"])
def view_note(note_id: int):
    n = db.session.get(Note, note_id)
    if not n:
        return jsonify({"error": "not_found"}), 404
    fp = _fingerprint_from_request(request)
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

@limiter.limit("30/minute")
@api.route("/notes/<int:note_id>/report", methods=["POST"])
def report_note(note_id: int):
    n = db.session.get(Note, note_id)
    if not n:
        return jsonify({"error": "not_found"}), 404
    fp = _fingerprint_from_request(request)
    already = db.session.query(ReportLog.id).filter_by(note_id=note_id, fingerprint=fp).first()
    if already:
        return jsonify({"ok": True, "reports": n.reports or 0, "already_reported": True}), 200
    try:
        db.session.add(ReportLog(note_id=note_id, fingerprint=fp))
        n.reports = (n.reports or 0) + 1
        if n.reports >= 5:
            db.session.delete(n)
            db.session.commit()
            return jsonify({"ok": True, "deleted": True, "reports": 5}), 200
        db.session.commit()
        return jsonify({"ok": True, "reports": n.reports}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": "report_failed", "detail": str(e)}), 500


@api.route("/admin/cleanup", methods=["POST","GET"])
def admin_cleanup():
    token = os.getenv("ADMIN_TOKEN","")
    provided = (request.args.get("token") or request.headers.get("X-Admin-Token") or "")
    if not token or provided != token:
        return jsonify({"error":"forbidden"}), 403
    try:
        from flask import current_app
        from backend.__init__ import _cleanup_once
        _cleanup_once(current_app)
        return jsonify({"ok": True}), 200
    except Exception as e:
        return jsonify({"error": "cleanup_failed", "detail": str(e)}), 500
@api.route("/notes", methods=["GET", "HEAD"])
def list_notes():
    try:
        after_id = request.args.get("after_id")
        try:
            limit = int((request.args.get("limit") or "20").strip() or "20")
        except Exception:
            limit = 20
        limit = max(1, min(limit, 50))

        q = db.session.query(Note).order_by(Note.id.desc())
        if after_id:
            try:
                aid = int(after_id)
                q = q.filter(Note.id < aid)
            except Exception:
                pass

        # Traer limit+1 para detectar si hay otra página
        items = q.limit(limit + 1).all()
        page = items[:limit]

        def _to(n):
            return {
                "id": n.id,
                "text": getattr(n, "text", None),
                "timestamp": n.timestamp.isoformat() if getattr(n, "timestamp", None) else None,
                "expires_at": n.expires_at.isoformat() if getattr(n, "expires_at", None) else None,
                "likes": getattr(n, "likes", 0) or 0,
                "views": getattr(n, "views", 0) or 0,
                "reports": getattr(n, "reports", 0) or 0,
            }

        from flask import jsonify
        resp = jsonify([_to(n) for n in page])
        if len(items) > limit and page:
            resp.headers["X-Next-After"] = str(page[-1].id)
        return resp, 200
    except Exception as e:
        from flask import jsonify
        return jsonify({"error": "list_failed", "detail": str(e)}), 500


@api.route("/_routes", methods=["GET"])
def api_routes_dump():
    from flask import current_app, jsonify
    info = []
    for r in current_app.url_map.iter_rules():
        info.append({
            "rule": str(r),
            "methods": sorted(m for m in r.methods if m not in ("HEAD","OPTIONS")),
            "endpoint": r.endpoint,
        })
    return jsonify({"routes": sorted(info, key=lambda x: x["rule"])}), 200
