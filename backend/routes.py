from flask import Blueprint, request, jsonify, Response, current_app
from sqlalchemy import text
from . import db

api_bp = Blueprint("api_bp", __name__)

@api_bp.route("/health", methods=["GET"])
def health():
    return jsonify(ok=True, api=True, ver="factory-min-v1")

@api_bp.route("/notes", methods=["OPTIONS"])
def notes_options():
    r = Response("", 204)
    r.headers["Access-Control-Allow-Origin"]  = "*"
    r.headers["Access-Control-Allow-Methods"] = "GET, POST, HEAD, OPTIONS"
    r.headers["Access-Control-Allow-Headers"] = "Content-Type"
    r.headers["Access-Control-Max-Age"]       = "86400"
    return r

@api_bp.route("/notes", methods=["GET"])
def get_notes():
    try:
        limit = min(int(request.args.get("limit", 10)), 50)
    except Exception:
        limit = 10
    before_id = request.args.get("before_id", type=int)

    sql = """
    SELECT id, text, timestamp, expires_at, likes, views, reports, author_fp
    FROM notes
    WHERE (:before_id IS NULL OR id < :before_id)
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
            last_id = data[-1]["id"]
            headers["Link"] = f'</api/notes?limit={limit}&before_id={last_id}>; rel="next"'
        return jsonify(data), 200, headers
    except Exception as e:
        current_app.logger.exception("get_notes failed")
        return jsonify(error="db_error", detail=str(e)), 500

def _bump(col, note_id: int):
    sql = f"UPDATE notes SET {col} = COALESCE({col},0) + 1 WHERE id = :id RETURNING {col}"
    with db.session.begin():
        res = db.session.execute(text(sql), {"id": note_id}).first()
        return int(res[0]) if res else None

@api_bp.route("/notes/<int:note_id>/like", methods=["POST"])
def like_note(note_id: int):
    try:
        val = _bump("likes", note_id)
        return jsonify(ok=True, id=note_id, likes=val), 200
    except Exception as e:
        current_app.logger.exception("like failed")
        return jsonify(error="db_error", detail=str(e)), 500

@api_bp.route("/notes/<int:note_id>/view", methods=["POST"])
def view_note(note_id: int):
    try:
        val = _bump("views", note_id)
        return jsonify(ok=True, id=note_id, views=val), 200
    except Exception as e:
        current_app.logger.exception("view failed")
        return jsonify(error="db_error", detail=str(e)), 500

@api_bp.route("/notes/<int:note_id>/report", methods=["POST"])
def report_note(note_id: int):
    try:
        val = _bump("reports", note_id)
        return jsonify(ok=True, id=note_id, reports=val), 200
    except Exception as e:
        current_app.logger.exception("report failed")
        return jsonify(error="db_error", detail=str(e)), 500
