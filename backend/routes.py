from __future__ import annotations

from flask import Blueprint, current_app, jsonify, request, make_response
from sqlalchemy import text
from urllib.parse import urlencode

api_bp = Blueprint("api", __name__)


@api_bp.get("/api/health")
def health():
    # Si este handler existe, significa que el blueprint se registró OK
    return jsonify(ok=True, api=True, ver="api-routes-v1")


@api_bp.route("/api/notes", methods=["OPTIONS"])
def options_notes():
    # flask-cors se encarga de los headers; devolvemos 204 vacío
    return ("", 204)


@api_bp.get("/api/notes")
def get_notes():
    limit = request.args.get("limit", default=10, type=int)
    before_id = request.args.get("before_id", type=int)

    sql = "SELECT id, text, timestamp, expires_at, likes, views, reports, author_fp FROM notes"
    params = {}
    if before_id is not None:
        sql += " WHERE id < :before_id"
        params["before_id"] = before_id
    sql += " ORDER BY timestamp DESC LIMIT :limit"
    params["limit"] = max(1, min(limit, 50))

    dbi = current_app.extensions["sqlalchemy"].db
    rows = dbi.session.execute(text(sql), params).mappings().all()
    data = [dict(r) for r in rows]

    resp = make_response(jsonify(data))
    if data:
        last_id = data[-1]["id"]
        resp.headers["Link"] = f"<{request.base_url}?{urlencode({'limit': params['limit'], 'before_id': last_id})}>; rel=\"next\""
    return resp


@api_bp.post("/api/notes/<int:note_id>/like")
def like_note(note_id: int):
    dbi = current_app.extensions["sqlalchemy"].db
    row = dbi.session.execute(
        text("UPDATE notes SET likes=COALESCE(likes,0)+1 WHERE id=:id RETURNING id, likes"),
        {"id": note_id},
    ).first()
    dbi.session.commit()
    if not row:
        return jsonify(error="not found"), 404
    return jsonify(ok=True, id=row.id, likes=row.likes)
