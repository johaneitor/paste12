from __future__ import annotations

import os, hashlib
from datetime import datetime, timedelta
from flask import send_from_directory,  Blueprint, request, jsonify, make_response
from backend import db

# Import del modelo Note
try:
    from backend.models import Note
except Exception as e:  # mostramos el error al golpear endpoints
    Note = None
    _import_error = e
else:
    _import_error = None

# Un único blueprint llamado "api"
bp = Blueprint("api", __name__)

def _now() -> datetime:
    # Naive UTC (compatible con la mayoría de definiciones típicas de modelos)
    return datetime.utcnow()

def _fp() -> str:
    try:
        ip = request.headers.get("X-Forwarded-For","") or request.headers.get("CF-Connecting-IP","") or (request.remote_addr or "")
        ua = request.headers.get("User-Agent","")
        salt = os.environ.get("FP_SALT","")
        return hashlib.sha256(f"{ip}|{ua}|{salt}".encode()).hexdigest()[:32]
    except Exception:
        return "noctx"

def _note_json(n: "Note", now: datetime | None = None) -> dict:
    now = now or _now()
    return {
        "id": n.id,
        "text": n.text,
        "timestamp": n.timestamp.isoformat() if hasattr(n.timestamp, "isoformat") else n.timestamp,
        "expires_at": n.expires_at.isoformat() if hasattr(n.expires_at, "isoformat") else n.expires_at,
        "likes": getattr(n, "likes", 0),
        "views": getattr(n, "views", 0),
        "reports": getattr(n, "reports", 0),
        "author_fp": getattr(n, "author_fp", None),
        "now": now.isoformat(),
    }

@bp.route("/health", methods=["GET"])
def health():
    return jsonify({"ok": True})

@bp.route("/notes", methods=["GET"])
def list_notes():
    if Note is None:
        return jsonify({"ok": False, "error": f"Note not importable: {_import_error!r}"}), 500
    try:
        page = int(request.args.get("page", 1))
    except Exception:
        page = 1
    page = max(1, page)
    per_page = 20
    q = Note.query.order_by(Note.timestamp.desc())
    items = q.limit(per_page).offset((page - 1) * per_page).all()
    now = _now()
    return jsonify([_note_json(n, now) for n in items]), 200

@bp.route("/notes", methods=["POST"])
def create_note():
    if Note is None:
        return jsonify({"ok": False, "error": f"Note not importable: {_import_error!r}"}), 500
    try:
        data = request.get_json(silent=True) or {}
        text = (data.get("text") or "").strip()
        if not text:
            return jsonify({"error": "text required"}), 400
        try:
            hours = int(data.get("hours", 24))
        except Exception:
            hours = 24
        hours = min(168, max(1, hours))
        now = _now()
        n = Note(
            text=text,
            timestamp=now,
            expires_at=now + timedelta(hours=hours),
            author_fp=_fp(),
        )
        db.session.add(n)
        db.session.commit()
        return jsonify(_note_json(n, now)), 201
    except Exception as e:
        db.session.rollback()
        return jsonify({"error":"create_failed", "detail": str(e)}), 500

@bp.route("/notes/<int:note_id>/like", methods=["POST"])
def like_note(note_id: int):
    if Note is None:
        return jsonify({"ok": False, "error": f"Note not importable: {_import_error!r}"}), 500
    n = Note.query.get(note_id)
    if not n:
        return jsonify({"error":"not_found"}), 404
    try:
        n.likes = int(getattr(n, "likes", 0)) + 1
        db.session.commit()
        return jsonify({"ok": True, "likes": n.likes, "id": n.id}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"error":"like_failed", "detail": str(e)}), 500

# === paste12: /api/reports (mínimo, usa SQLite directo) ============
import sqlite3, os
from flask import request, jsonify, make_response
DB_PATH = os.getenv("PASTE12_DB", "app.db")

def _db_path():
    for p in ("app.db", "instance/app.db", "data/app.db"):
        if os.path.exists(os.path.join(os.getcwd(), p)): return p
    return "app.db"

def _conn():
    path = _db_path()
    conn = sqlite3.connect(path, check_same_thread=False)
    conn.execute("PRAGMA journal_mode=WAL;")
    conn.execute("PRAGMA synchronous=NORMAL;")
    conn.execute("PRAGMA busy_timeout=5000;")
    conn.row_factory = sqlite3.Row
    return conn

@bp.route("/reports", methods=["POST"])
def create_report_min():
    try:
        j = request.get_json(force=True, silent=True) or {}
        cid = str(j.get("content_id","")).strip()
        if not cid:
            return jsonify({"error":"content_id_required"}), 400
        fp = request.headers.get("X-Forwarded-For") or request.remote_addr or "anon"
        con = _conn()
        con.execute("INSERT OR IGNORE INTO reports(content_id, reporter_id, reason) VALUES(?,?,?)",
                    (cid, fp, j.get("reason")))
        con.commit()
        c = int(con.execute("SELECT COUNT(*) FROM reports WHERE content_id=?", (cid,)).fetchone()[0])
        con.close()
        deleted = False  # (opcional) acá podrías ocultar la nota si c>=5
        return jsonify({"ok": True, "count": c, "deleted": deleted}), 200
    except Exception as e:
        return jsonify({"error":"report_failed","detail":str(e)}), 500


@app.route('/terms', methods=['GET','HEAD'])
def terms():
    return send_from_directory('frontend','terms.html')


@app.route('/privacy', methods=['GET','HEAD'])
def privacy():
    return send_from_directory('frontend','privacy.html')

@app.route('/api/notes', methods=['HEAD'])
def api_notes_head():
    # Respuesta vacía para HEAD con CORS estándar
    resp = make_response('', 200)
    resp.headers['Access-Control-Allow-Origin'] = '*'
    resp.headers['Access-Control-Allow-Methods'] = 'GET, POST, HEAD, OPTIONS'
    resp.headers['Access-Control-Allow-Headers'] = 'Content-Type'
    resp.headers['Access-Control-Max-Age'] = '86400'
    # Opcional: tipo json para clientes que lo esperan aunque no haya body
    resp.headers['Content-Type'] = 'application/json'
    return resp


# --- compat: evitar 405 por trailing slash en /api/notes/
try:
    from flask import Blueprint, redirect, request
    from flask import current_app as _cur
    bp  # noqa: F401
except Exception:
    pass
else:
    @bp.route("/api/notes/", methods=["GET","POST","OPTIONS"], strict_slashes=False)
    def _notes_slash_compat():
        # 307 mantiene método y body para POST
        return redirect("/api/notes", code=307)


# --- no-cache en HTML para evitar servir versiones viejas
try:
    from flask import after_this_request
    from flask import current_app as _cur
except Exception:
    pass
else:
    try:
        @bp.after_request
        def _add_nocache_headers(resp):
            ct = resp.headers.get("Content-Type","")
            if ct.startswith("text/html"):
                resp.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
                resp.headers["Pragma"] = "no-cache"
            return resp
    except Exception:
        pass
