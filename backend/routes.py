from flask import Blueprint, request, jsonify, Response, current_app, abort
from sqlalchemy import text
from datetime import datetime, timedelta
from . import db
from .models import Note, NoteReport
from . import limiter
import base64
import json as _json
import hashlib

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

    sql_main = """
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
    sql_fallback_notes = """
    SELECT id, text, timestamp, expires_at, likes, views, reports, author_fp
    FROM notes
    WHERE (:before_id IS NULL OR id < :before_id)
      AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP)
    ORDER BY id DESC
    LIMIT :limit
    """
    sql_fallback_note = """
    SELECT id, text, timestamp, expires_at, likes, views, reports, author_fp
    FROM note
    WHERE (:before_id IS NULL OR id < :before_id)
      AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP)
    ORDER BY id DESC
    LIMIT :limit
    """
    try:
        with db.session.begin():
            try:
                rows = db.session.execute(
                    text(sql_main),
                    {"before_id": before_id, "limit": limit},
                ).mappings().all()
            except Exception:
                # Fallback si no existe note_report o la tabla 'notes' no existe
                try:
                    rows = db.session.execute(
                        text(sql_fallback_notes),
                        {"before_id": before_id, "limit": limit},
                    ).mappings().all()
                except Exception:
                    rows = db.session.execute(
                        text(sql_fallback_note),
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
        expires_at = now + timedelta(hours=hours)
        note = Note(text=text_body, timestamp=now, expires_at=expires_at)
        db.session.add(note)
        db.session.commit()
        new_id = note.id

        # Capacity enforcement (CAP=400): evict least relevant then oldest
        try:
            cap = 400
            with db.session.begin():
                total = None
                victims = []
                # Main table name 'notes'
                try:
                    total = db.session.execute(text("SELECT COUNT(*) FROM notes")).scalar() or 0
                except Exception:
                    total = db.session.execute(text("SELECT COUNT(*) FROM note")).scalar() or 0
                if total and total > cap:
                    to_delete = total - cap
                    # Prefer not to delete the just-created note
                    try:
                        victims = db.session.execute(text(
                            """
                            SELECT id FROM notes
                            WHERE id <> :new_id AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP)
                            ORDER BY (COALESCE(likes,0)+COALESCE(views,0)) ASC, timestamp ASC
                            LIMIT :n
                            """
                        ), {"n": to_delete, "new_id": new_id}).scalars().all()
                    except Exception:
                        victims = db.session.execute(text(
                            """
                            SELECT id FROM note
                            WHERE id <> :new_id AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP)
                            ORDER BY (COALESCE(likes,0)+COALESCE(views,0)) ASC, timestamp ASC
                            LIMIT :n
                            """
                        ), {"n": to_delete, "new_id": new_id}).scalars().all()
                    if victims:
                        # Try ANSI
                        try:
                            db.session.execute(text("DELETE FROM notes WHERE id = ANY(:ids)"), {"ids": victims})
                        except Exception:
                            pass
                        # Fallback generic IN clause
                        ids = ",".join(str(i) for i in victims)
                        try:
                            db.session.execute(text(f"DELETE FROM notes WHERE id IN ({ids})"))
                        except Exception:
                            db.session.execute(text(f"DELETE FROM note WHERE id IN ({ids})"))
        except Exception:
            db.session.rollback()

        # Build response body from known local values to avoid refresh after commit
        body = {
            "id": new_id,
            "text": text_body,
            "timestamp": now.isoformat(),
            "expires_at": expires_at.isoformat() if expires_at else None,
            "likes": 0,
            "views": 0,
            "reports": 0,
            "author_fp": None,
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


def _client_fingerprint() -> str:
    ip = request.headers.get("X-Forwarded-For", "") or request.headers.get("CF-Connecting-IP", "") or (request.remote_addr or "")
    ua = request.headers.get("User-Agent", "")
    salt = (request.headers.get("X-Client-Salt") or request.cookies.get("p12uid") or "")
    return hashlib.sha256(f"{ip}|{ua}|{salt}".encode()).hexdigest()


def _like_once(note_id: int):
    fp = _client_fingerprint()
    # check existence
    exists = False
    try:
        row = db.session.execute(text("SELECT 1 FROM note_like WHERE note_id=:nid AND fp=:fp LIMIT 1"), {"nid": note_id, "fp": fp}).first()
        exists = bool(row)
    except Exception:
        # try create table if missing (non-intrusive)
        try:
            db.session.execute(text(
                """
                CREATE TABLE IF NOT EXISTS note_like (
                  note_id INTEGER NOT NULL,
                  fp TEXT NOT NULL,
                  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                  UNIQUE(note_id, fp)
                )
                """
            ))
            db.session.commit()
        except Exception:
            db.session.rollback()
    if exists:
        # read current likes
        val = db.session.execute(text("SELECT COALESCE(likes,0) FROM notes WHERE id=:nid"), {"nid": note_id}).scalar()
        if val is None:
            val = db.session.execute(text("SELECT COALESCE(likes,0) FROM note WHERE id=:nid"), {"nid": note_id}).scalar() or 0
        return int(val)
    # insert and bump
    inserted = False
    try:
        try:
            db.session.execute(text("INSERT INTO note_like(note_id, fp) VALUES (:nid, :fp) ON CONFLICT (note_id, fp) DO NOTHING"), {"nid": note_id, "fp": fp})
            inserted = True
        except Exception:
            db.session.execute(text("INSERT OR IGNORE INTO note_like(note_id, fp) VALUES (:nid, :fp)"), {"nid": note_id, "fp": fp})
            inserted = True
        db.session.commit()
    except Exception:
        db.session.rollback()
    # bump only if we could register
    if inserted:
        n, code = _bump(note_id, "likes", 1)
        if code == 200 and n is not None:
            return int(getattr(n, "likes", 0) or 0)
    # fallback: return current value
    val = db.session.execute(text("SELECT COALESCE(likes,0) FROM notes WHERE id=:nid"), {"nid": note_id}).scalar()
    if val is None:
        val = db.session.execute(text("SELECT COALESCE(likes,0) FROM note WHERE id=:nid"), {"nid": note_id}).scalar() or 0
    return int(val)

@api_bp.route("/notes/<int:note_id>/like", methods=["POST"])
@limiter.limit("30 per minute")
@limiter.limit("1 per minute", key_func=lambda: f"{request.remote_addr}|{request.view_args.get('note_id') if request.view_args else request.args.get('id')}")
def like_note(note_id: int):
    try:
        # idempotent like per fingerprint
        # ensure note exists first
        exists = db.session.execute(text("SELECT 1 FROM notes WHERE id=:nid"), {"nid": note_id}).first()
        if not exists:
            abort(404)
        val = _like_once(note_id)
        return jsonify(ok=True, id=note_id, likes=val), 200
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


@api_bp.route("/like", methods=["GET", "POST"])
@limiter.limit("30 per minute")
def like_alias():
    # Validate before rate-limit edge cases → ensure 400/404 precedence
    note_id = _get_id_param()
    n, code = _bump(note_id, "likes", 1)
    if code == 404:
        abort(404)
    if code == 400:
        return jsonify(error="bad_column"), 400
    return jsonify(ok=True, id=note_id, likes=n.likes), 200


@api_bp.route("/report", methods=["GET", "POST"])
@limiter.limit("30 per minute")
def report_alias():
    # Validate before applying limit-specific logic
    raw = request.args.get("id") or request.form.get("id")
    if not raw:
        abort(404)
    try:
        note_id = int(raw)
    except Exception:
        abort(404)
    return report_note(note_id)


@api_bp.route("/view", methods=["GET", "POST"])
@limiter.limit("600 per minute")
def view_alias():
    raw = request.args.get("id") or request.form.get("id")
    if not raw:
        abort(404)
    try:
        note_id = int(raw)
    except Exception:
        abort(404)
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


# Pre-guard for legacy alias /api/report to ensure 404 on missing/invalid id
@api_bp.before_app_request
def _guard_alias_report_bad_id():
    try:
        if request.path == "/api/report" and request.method in ("GET", "POST"):
            raw = request.args.get("id") or request.form.get("id")
            if not raw:
                return jsonify(error="bad_id"), 404
            try:
                int(raw)
            except Exception:
                return jsonify(error="bad_id"), 404
    except Exception:
        # Fail-open to avoid blocking legitimate requests
        return None
