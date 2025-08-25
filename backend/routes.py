from __future__ import annotations
from flask import Blueprint, request, jsonify, send_from_directory
import datetime as _dt
import sqlalchemy as sa
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
        db.session.add(ViewLog(note_id=note_id, fingerprint=fp, view_date=today, day=today))
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

# --- runtime diag ---
try:
    from flask import current_app, jsonify
    @api.route("/runtime", methods=["GET"])  # type: ignore
    def runtime():
        import sys
        try:
            from backend.webui import FRONT_DIR as _FD  # type: ignore
            front_dir = str(_FD); front_dir_exists = _FD.exists()
        except Exception:
            front_dir, front_dir_exists = None, False
        rules = sorted(
            [{"rule": r.rule, "methods": sorted(r.methods)} for r in current_app.url_map.iter_rules()],
            key=lambda x: x["rule"]
        )
        return jsonify({
            "uses_backend_entry": "backend.entry" in sys.modules,
            "has_root_route": any(r["rule"]=="/" for r in rules),
            "front_dir": front_dir,
            "front_dir_exists": front_dir_exists,
            "rules_sample": rules[:50],
        })
except Exception:
    pass

from pathlib import Path
from flask import request, jsonify

@api.route("/fs", methods=["GET"])  # /api/fs?path=backend/frontend
def api_fs():
    q = request.args.get("path", ".")
    p = Path(q)
    info = {
        "path": str(p.resolve()),
        "exists": p.exists(),
        "is_dir": p.is_dir(),
        "list": None,
    }
    if p.exists() and p.is_dir():
        try:
            info["list"] = sorted([x for x in p.iterdir() if x.name[:1] != "." and x.is_file() or x.is_dir()])[:200]
            info["list"] = [str(x.name) for x in info["list"]]
        except Exception as e:
            info["list_error"] = str(e)
    return jsonify(info), 200

# --- UI debug mount under /api/ui/* (no depende del blueprint webui) ---
try:
    from flask import send_from_directory
    from backend.webui import FRONT_DIR as _FD  # dónde están los archivos del frontend

    @api.route("/ui", methods=["GET"])               # -> /api/ui
    def ui_index():
        return send_from_directory(_FD, "index.html")

    @api.route("/ui/js/<path:fname>", methods=["GET"])
    def ui_js(fname):
        return send_from_directory(_FD / "js", fname)

    @api.route("/ui/css/<path:fname>", methods=["GET"])
    def ui_css(fname):
        return send_from_directory(_FD / "css", fname)

    @api.route("/ui/robots.txt", methods=["GET"])
    def ui_robots():
        p = _FD / "robots.txt"
        return (send_from_directory(_FD, "robots.txt") if p.exists() else ("", 204))

    @api.route("/ui/favicon.ico", methods=["GET"])
    def ui_favicon():
        p = _FD / "favicon.ico"
        return (send_from_directory(_FD, "favicon.ico") if p.exists() else ("", 204))
except Exception:
    # No rompemos el API si algo falla
    pass

from flask import current_app, jsonify
import sqlalchemy as sa

@api.route("/dbdiag", methods=["GET"])  # type: ignore
def dbdiag():
    out = {}
    try:
        from backend import db  # type: ignore
        out["has_db"] = True
        # ¿la session tiene bind?
        try:
            bind = db.session.get_bind()
            out["session_bind"] = bool(bind)
            out["engine_str"] = str(bind.url) if bind else None
        except Exception as e:
            out["session_bind"] = False
            out["session_bind_err"] = str(e)

        # ¿puedo ejecutar SELECT 1?
        try:
            with current_app.app_context():
                conn = db.engine.connect()
                conn.execute(sa.text("SELECT 1"))
                conn.close()
            out["engine_ok"] = True
        except Exception as e:
            out["engine_ok"] = False
            out["engine_err"] = str(e)
    except Exception as e:
        out["has_db"] = False
        out["err"] = str(e)
    return jsonify(out), 200


# Limpieza oportunista simple, rate-limited en 60s
_last_cleanup_ts = 0
def _maybe_cleanup_expired(db, Note, LikeLog=None, ReportLog=None, ViewLog=None, max_batch=200):
    global _last_cleanup_ts
    import time
    now=time.time()
    if now - _last_cleanup_ts < 60:
        return 0
    _last_cleanup_ts = now
    cutoff = _dt.datetime.utcnow()
    try:
        exp = db.session.query(Note.id).filter(Note.expires_at != None, Note.expires_at <= cutoff).limit(max_batch).all()
        ids=[x[0] if isinstance(x,tuple) else getattr(x,'id',None) for x in exp]
        ids=[i for i in ids if i is not None]
        if not ids: return 0
        for Log in (LikeLog, ReportLog, ViewLog):
            if Log is None: continue
            db.session.query(Log).filter(Log.note_id.in_(ids)).delete(synchronize_session=False)
        db.session.query(Note).filter(Note.id.in_(ids)).delete(synchronize_session=False)
        db.session.commit()
        return len(ids)
    except Exception:
        db.session.rollback()
        return 0
