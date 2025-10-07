from flask import Blueprint, request, jsonify, Response, current_app, abort
from sqlalchemy import text
from datetime import datetime, timedelta
from . import db
from .models import Note, NoteReport
from . import limiter
import base64
import json as _json

api_bp = Blueprint("api_bp", __name__)

@api_bp.route("/health", methods=["GET"])
def health():
    return jsonify(ok=True, status="ok", api=True, ver="factory-min-v1")

@api_bp.route("/notes", methods=["OPTIONS"])
def notes_options():
    r = Response("", 204)
    r.headers["Access-Control-Allow-Origin"]  = "*"
    r.headers["Access-Control-Allow-Methods"] = "GET, POST, HEAD, OPTIONS"
    r.headers["Access-Control-Allow-Headers"] = "Content-Type"
    r.headers["Access-Control-Max-Age"]       = "86400"
    r.headers["Allow"] = "GET, POST, HEAD, OPTIONS"
    return r

def _parse_next(cursor: str | None):
    if not cursor:
        return None
    try:
        raw = base64.urlsafe_b64decode(cursor.encode()).decode()
        data = _json.loads(raw)
        return {
            "before_id": int(data.get("before_id")) if data.get("before_id") else None,
        }
    except Exception:
        return None


def _make_next(last_id: int | None, limit: int):
    if not last_id:
        return None
    payload = {"before_id": last_id, "limit": limit}
    return base64.urlsafe_b64encode(_json.dumps(payload).encode()).decode()


@api_bp.route("/notes", methods=["GET"])
def get_notes():
    try:
        limit = max(1, min(int(request.args.get("limit", 10)), 50))
    except Exception:
        limit = 10
    before_id = request.args.get("before_id", type=int)
    nxt = _parse_next(request.args.get("next"))
    if nxt and nxt.get("before_id"):
        before_id = nxt["before_id"]

    sql = """
    SELECT id, text, timestamp, expires_at, likes, views, reports, author_fp
    FROM notes
    WHERE (:before_id IS NULL OR id < :before_id)
      AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP)
      AND (
        SELECT COUNT(DISTINCT reporter_hash)
        FROM note_report nr
        WHERE nr.note_id = notes.id
      ) < 3
    ORDER BY id DESC
    LIMIT :limit
    """
    try:
        with db.session.begin():
            rows = db.session.execute(
                text(sql),
                {"before_id": before_id, "limit": limit},
            ).mappings().all()
        data = [dict(r) for r in rows]
        # Link header para paginación simple
        headers = {}
        if len(data) == limit and data:
            last = data[-1]
            last_id = last["id"]
            # Include timestamp to harden cursor
            try:
                last_ts = last.get("timestamp")
            except Exception:
                last_ts = None
            opaque = _make_next(last_id, limit)
            headers["Link"] = f'</api/notes?limit={limit}&next={opaque}>; rel="next"'
        return jsonify({"notes": data}), 200, headers
    except Exception as e:
        current_app.logger.exception("get_notes failed")
        return jsonify(error="db_error", detail=str(e)), 500


@api_bp.route("/notes", methods=["POST"])
@limiter.limit("5 per minute")
def create_note():
    try:
        # Soporta JSON o form
        data = request.get_json(silent=True) or request.form or {}
        text_body = (data.get("text") or data.get("content") or "").strip()
        if not text_body:
            return jsonify(error="text required"), 400

        # ttlHours alias (spec) + hours fallback
        try:
            hours = int(data.get("ttlHours", data.get("ttl_hours", data.get("hours", 144))))
        except Exception:
            hours = 144
        hours = min(168, max(1, hours))

        now = datetime.utcnow()
        note = Note(
            text=text_body,
            timestamp=now,
            expires_at=now + timedelta(hours=hours),
        )
        db.session.add(note)
        db.session.commit()

        # Capacity enforcement (CAP=400): evict least relevant then oldest
        try:
            cap = 400
            with db.session.begin():
                total = db.session.execute(text("SELECT COUNT(*) FROM notes")).scalar() or 0
                if total > cap:
                    to_delete = total - cap
                    victims = db.session.execute(text(
                        """
                        SELECT id FROM notes
                        WHERE (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP)
                        ORDER BY (COALESCE(likes,0)+COALESCE(views,0)) ASC, timestamp ASC
                        LIMIT :n
                        """
                    ), {"n": to_delete}).scalars().all()
                    if victims:
                        db.session.execute(text("DELETE FROM notes WHERE id = ANY(:ids)"), {"ids": victims})
                        # SQLite fallback
                        db.session.execute(text("DELETE FROM notes WHERE id IN (" + ",".join(str(i) for i in victims) + ")"))
        except Exception:
            db.session.rollback()

        body = {
            "id": note.id,
            "text": note.text,
            "timestamp": note.timestamp.isoformat(),
            "expires_at": note.expires_at.isoformat() if note.expires_at else None,
            "likes": note.likes,
            "views": note.views,
            "reports": note.reports,
            "author_fp": getattr(note, "author_fp", None),
        }
        # Aliases for external scripts
        body["created_at"] = body["timestamp"]
        body["ttl_expire_at"] = body["expires_at"]
        return jsonify(body), 201
    except Exception as e:
        current_app.logger.exception("create_note failed")
        db.session.rollback()
        return jsonify(error="db_error", detail=str(e)), 500

ALLOWED_COUNTERS = {
    "likes": Note.likes,
    "views": Note.views,
    "reports": Note.reports,
}


def _bump(note_id: int, column: str, delta: int = 1):
    col = ALLOWED_COUNTERS.get(column)
    if col is None:
        return None, 400
    q = db.session.query(Note).filter(Note.id == note_id)
    updated = q.update({col: col + delta}, synchronize_session=False)
    if updated == 0:
        return None, 404
    db.session.commit()
    n = db.session.get(Note, note_id)
    return n, 200

@api_bp.route("/notes/<int:note_id>/like", methods=["POST"])
@limiter.limit("30 per minute")
@limiter.limit("1 per minute", key_func=lambda: f"{request.remote_addr}|{request.view_args.get('note_id') if request.view_args else request.args.get('id')}")
def like_note(note_id: int):
    try:
        n, code = _bump(note_id, "likes", 1)
        if code == 404:
            abort(404)
        if code == 400:
            return jsonify(error="bad_column"), 400
        return jsonify(ok=True, id=note_id, likes=n.likes), 200
    except Exception as e:
        current_app.logger.exception("like failed")
        return jsonify(error="db_error", detail=str(e)), 500

@api_bp.route("/notes/<int:note_id>/view", methods=["POST"])
@limiter.limit("60 per minute")
@limiter.limit("1 per minute", key_func=lambda: f"{request.remote_addr}|{request.headers.get('User-Agent','-')}|{request.view_args.get('note_id') if request.view_args else request.args.get('id')}")
def view_note(note_id: int):
    try:
        n, code = _bump(note_id, "views", 1)
        if code == 404:
            abort(404)
        if code == 400:
            return jsonify(error="bad_column"), 400
        return jsonify(ok=True, id=note_id, views=n.views), 200
    except Exception as e:
        current_app.logger.exception("view failed")
        return jsonify(error="db_error", detail=str(e)), 500

@api_bp.route("/notes/<int:note_id>/report", methods=["POST"])
@limiter.limit("30 per minute")
@limiter.limit("1 per minute", key_func=lambda: f"{request.remote_addr}|{request.view_args.get('note_id') if request.view_args else request.args.get('id')}")
def report_note(note_id: int):
    try:
        # Register unique reporter and auto-delete after 3 unique reports
        ip = request.headers.get("X-Forwarded-For", "") or request.headers.get("CF-Connecting-IP", "") or (request.remote_addr or "")
        ua = request.headers.get("User-Agent", "")
        import hashlib
        reporter_hash = hashlib.sha256(f"{ip}|{ua}|{note_id}".encode()).hexdigest()[:64]
        try:
            db.session.add(NoteReport(note_id=note_id, reporter_hash=reporter_hash))
            db.session.commit()
        except Exception:
            db.session.rollback()  # duplicate or other issue, continue

        n, code = _bump(note_id, "reports", 1)
        if code == 404:
            abort(404)
        if code == 400:
            return jsonify(error="bad_column"), 400

        # Soft-delete once threshold reached
        try:
            res = db.session.execute(
                text("SELECT COUNT(DISTINCT reporter_hash) AS c FROM note_report WHERE note_id=:nid"),
                {"nid": note_id},
            ).first()
            unique_count = int(res[0]) if res else 0
            if unique_count >= 3 and not getattr(n, "deleted_at", None):
                now = datetime.utcnow()
                db.session.query(Note).filter(Note.id == note_id).update({Note.deleted_at: now}, synchronize_session=False)
                db.session.commit()
        except Exception:
            db.session.rollback()

        return jsonify(ok=True, id=note_id, reports=n.reports), 200
    except Exception as e:
        current_app.logger.exception("report failed")
        return jsonify(error="db_error", detail=str(e)), 500


@api_bp.get("/health/db")
def health_db():
    try:
        db.session.execute(text("SELECT 1"))
        return jsonify(db="ok"), 200
    except Exception as e:
        current_app.logger.exception("health_db failed")
        return jsonify(db="error", detail=str(e)), 503


@api_bp.get("/deploy-stamp")
def deploy_stamp():
    import os
    for k in ("RENDER_GIT_COMMIT", "GIT_COMMIT", "SOURCE_COMMIT", "COMMIT_SHA"):
        v = os.environ.get(k)
        if v:
            return jsonify(commit=v, source="env"), 200
    return jsonify(error="not_found"), 404


# --- Legacy alias endpoints (/api/like|view|report?id=...) ---

def _get_id_param() -> int:
    raw = request.args.get("id") or request.form.get("id")
    if not raw:
        abort(400)
    try:
        return int(raw)
    except Exception:
        abort(400)


@api_bp.route("/like", methods=["POST"])
@limiter.limit("10 per minute")
@limiter.limit("1 per minute", key_func=lambda: f"{request.remote_addr}|{request.args.get('id') or request.form.get('id')}")
def like_alias():
    note_id = _get_id_param()
    n, code = _bump(note_id, "likes", 1)
    if code == 404:
        abort(404)
    if code == 400:
        return jsonify(error="bad_column"), 400
    return jsonify(ok=True, id=note_id, likes=n.likes), 200


@api_bp.route("/report", methods=["POST"])
@limiter.limit("10 per minute")
@limiter.limit("1 per minute", key_func=lambda: f"{request.remote_addr}|{request.args.get('id') or request.form.get('id')}")
def report_alias():
    note_id = _get_id_param()
    return report_note(note_id)


@api_bp.route("/view", methods=["GET", "POST"])
@limiter.limit("60 per minute")
@limiter.limit("1 per minute", key_func=lambda: f"{request.remote_addr}|{request.headers.get('User-Agent','-')}|{request.args.get('id') or request.form.get('id')}")
def view_alias():
    raw = request.args.get("id") or request.form.get("id")
    if not raw:
        abort(400)
    try:
        note_id = int(raw)
    except Exception:
        abort(400)
    n, code = _bump(note_id, "views", 1)
    if code == 404:
        abort(404)
    if code == 400:
        return jsonify(error="bad_column"), 400
    return jsonify(ok=True, id=note_id, views=n.views), 200


# Ensure JSON endpoints are not cached (responses under /api/*)
@api_bp.after_app_request
def _api_no_cache(resp):
    try:
        if request.path.startswith("/api/"):
            ct = (resp.headers.get("Content-Type", "").lower())
            if "application/json" in ct:
                # 'no-cache' per acceptance; avoid caching intermediaries
                resp.headers["Cache-Control"] = "no-cache"
    except Exception:
        pass
    return resp
