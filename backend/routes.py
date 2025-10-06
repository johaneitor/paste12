from __future__ import annotations
import base64, json
from datetime import datetime, timezone, timedelta
from flask import Blueprint, request, jsonify, Response, current_app
from flask_cors import cross_origin
from sqlalchemy import text
from . import db

api_bp = Blueprint("api_bp", __name__)

@api_bp.route("/health", methods=["GET"])
def health():
    return jsonify(ok=True, api=True, ver="factory-min-v1")

@api_bp.route("/notes", methods=["OPTIONS"])
@cross_origin(origins="*")
def notes_options():
    r = Response("", 204)
    h = r.headers
    h["Access-Control-Allow-Origin"]  = "*"
    h["Access-Control-Allow-Methods"] = "GET, POST, HEAD, OPTIONS"
    h["Access-Control-Allow-Headers"] = "Content-Type, Accept"
    h["Access-Control-Max-Age"]       = "86400"
    h["Allow"]                          = "GET, POST, HEAD, OPTIONS"
    return r


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _ensure_aux_tables() -> None:
    """Create auxiliary tables used for abuse/report tracking, idempotently."""
    try:
        with db.session.begin():
            db.session.execute(text(
                """
                CREATE TABLE IF NOT EXISTS note_reports (
                  note_id   INTEGER NOT NULL,
                  fp        TEXT    NOT NULL,
                  ts        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                  PRIMARY KEY (note_id, fp)
                )
                """
            ))
    except Exception:
        db.session.rollback()

def _encode_next(ts: datetime, nid: int) -> str:
    payload = {"ts": ts.isoformat(), "id": int(nid)}
    raw = json.dumps(payload).encode("utf-8")
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def _decode_next(token: str) -> tuple[datetime, int] | None:
    try:
        pad = '=' * (-len(token) % 4)
        raw = base64.urlsafe_b64decode(token + pad)
        obj = json.loads(raw.decode("utf-8"))
        ts = datetime.fromisoformat(obj.get("ts"))
        if ts.tzinfo is None:
            ts = ts.replace(tzinfo=timezone.utc)
        nid = int(obj.get("id"))
        return ts, nid
    except Exception:
        return None


@api_bp.route("/notes", methods=["GET", "HEAD"])
@cross_origin(origins="*")
def get_notes():
    # clamp limit 1..50 (default 10)
    try:
        limit = int(request.args.get("limit", 10))
    except Exception:
        limit = 10
    if limit < 1:
        limit = 1
    if limit > 50:
        limit = 50

    nxt = request.args.get("next")
    cursor = _decode_next(nxt) if nxt else None

    try:
        # Excluir expiradas
        sql = (
            "SELECT id, text, timestamp, expires_at, likes, views, reports, author_fp "
            "FROM notes WHERE (expires_at IS NULL OR expires_at > NOW())"
        )
        params: dict[str, object] = {}
        if cursor is not None:
            ts, cid = cursor
            # ts/id cursor: estricto (< ts) o (= ts and id < cid)
            sql += " AND (timestamp < :ts OR (timestamp = :ts AND id < :cid))"
            params.update({"ts": ts, "cid": cid})
        sql += " ORDER BY timestamp DESC, id DESC LIMIT :limit"
        params["limit"] = limit

        with db.session.begin():
            rows = db.session.execute(text(sql), params).mappings().all()
        items = [dict(r) for r in rows]

        headers = {}
        if len(items) == limit and items:
            last = items[-1]
            lts = last["timestamp"]
            if isinstance(lts, str):
                try:
                    lts = datetime.fromisoformat(lts)
                except Exception:
                    lts = _now()
            if getattr(lts, "tzinfo", None) is None:
                lts = lts.replace(tzinfo=timezone.utc)
            token = _encode_next(lts, int(last["id"]))
            headers["Link"] = f'</api/notes?limit={limit}&next={token}>; rel="next"'

        return jsonify({"items": items}), 200, headers
    except Exception as e:
        current_app.logger.exception("get_notes failed")
        return jsonify(error="db_error", detail=str(e)), 500


@api_bp.route("/notes", methods=["POST"])
@cross_origin(origins="*")
def create_note():
    _ensure_aux_tables()
    # simple rate limit: 30/min per IP
    try:
        ip = (request.headers.get("X-Forwarded-For", "").split(",")[0].strip() or (request.remote_addr or ""))
        key = f"post:{ip}"
        # naive in-memory limiter (best-effort)
        from flask import current_app as _ca
        store = getattr(_ca, "_p12_rl_store", None)
        now = int(datetime.now(timezone.utc).timestamp())
        if store is None:
            store = _ca._p12_rl_store = {}
        wnd = now // 60
        cnt = store.get((key, wnd), 0)
        if cnt >= 30:
            return jsonify(error="too_many_requests"), 429
        store[(key, wnd)] = cnt + 1
    except Exception:
        pass
    data = {}
    if request.is_json:
        data = request.get_json(silent=True) or {}
    else:
        try:
            data = request.form.to_dict(flat=True)
        except Exception:
            data = {}

    text_val = (data.get("text") or "").strip()
    if not text_val:
        return jsonify(error="text_required"), 400
    if len(text_val) > 10_000:
        return jsonify(error="text_too_long"), 400

    try:
        hours = int(data.get("hours") or data.get("ttl") or data.get("ttl_hours") or 12)
    except Exception:
        hours = 12
    # clamp 1..144h
    hours = max(1, min(144, hours))

    now = _now()
    sql = (
        "INSERT INTO notes(text, timestamp, expires_at, likes, views, reports) "
        "VALUES (:text, :ts, :exp, 0, 0, 0) RETURNING id, timestamp"
    )
    try:
        with db.session.begin():
            row = db.session.execute(text(sql), {
                "text": text_val,
                "ts": now,
                "exp": now + timedelta(hours=hours),
            }).first()
        # Housekeeping: TTL purge and CAP 400
        _housekeeping_limits()
        return jsonify(id=int(row[0]), created_at=str(row[1])), 201
    except Exception as e:
        current_app.logger.exception("create_note failed")
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
        if val is None:
            return jsonify(error="not_found"), 404
        return jsonify(ok=True, id=note_id, likes=val), 200
    except Exception as e:
        current_app.logger.exception("like failed")
        return jsonify(error="db_error", detail=str(e)), 500

@api_bp.route("/notes/<int:note_id>/view", methods=["POST"])
def view_note(note_id: int):
    try:
        val = _bump("views", note_id)
        if val is None:
            return jsonify(error="not_found"), 404
        return jsonify(ok=True, id=note_id, views=val), 200
    except Exception as e:
        current_app.logger.exception("view failed")
        return jsonify(error="db_error", detail=str(e)), 500

@api_bp.route("/notes/<int:note_id>/report", methods=["POST"])
def report_note(note_id: int):
    try:
        val = _bump("reports", note_id)
        if val is None:
            return jsonify(error="not_found"), 404
        return jsonify(ok=True, id=note_id, reports=val), 200
    except Exception as e:
        current_app.logger.exception("report failed")
        return jsonify(error="db_error", detail=str(e)), 500


def _housekeeping_limits() -> None:
    """Purge expired (TTL) and enforce CAP=400 by low relevance+age."""
    try:
        with db.session.begin():
            # TTL purge
            db.session.execute(text("DELETE FROM notes WHERE expires_at IS NOT NULL AND expires_at <= NOW()"))
            # CAP enforcement
            cnt = db.session.execute(text("SELECT COUNT(*) FROM notes")).scalar() or 0
            cap = 400
            if cnt > cap:
                excess = int(cnt - cap)
                db.session.execute(text(
                    """
                    DELETE FROM notes WHERE id IN (
                      SELECT id FROM notes
                      ORDER BY COALESCE(likes,0)+COALESCE(views,0) ASC, timestamp ASC
                      LIMIT :excess
                    )
                    """
                ), {"excess": excess})
    except Exception:
        db.session.rollback()


# Root-style REST helpers (accept id via query) per contract
def _require_id_arg() -> int | Response:
    sid = request.args.get("id") if request.method == "GET" else (
        (request.get_json(silent=True) or {}).get("id") if request.is_json else request.form.get("id")
    )
    try:
        return int(sid)
    except Exception:
        return Response(json.dumps({"error": "bad_id"}), 400, [("Content-Type", "application/json")])


@api_bp.route("/like", methods=["GET", "POST"])
@cross_origin(origins="*")
def like_root():
    nid = _require_id_arg()
    if isinstance(nid, Response):
        return nid
    try:
        val = _bump("likes", nid)
        if val is None:
            return jsonify(error="not_found"), 404
        return jsonify(ok=True, id=nid, likes=val), 200
    except Exception as e:
        current_app.logger.exception("like root failed")
        return jsonify(error="db_error", detail=str(e)), 500


@api_bp.route("/view", methods=["GET", "POST"])
@cross_origin(origins="*")
def view_root():
    nid = _require_id_arg()
    if isinstance(nid, Response):
        return nid
    try:
        val = _bump("views", nid)
        if val is None:
            return jsonify(error="not_found"), 404
        return jsonify(ok=True, id=nid, views=val), 200
    except Exception as e:
        current_app.logger.exception("view root failed")
        return jsonify(error="db_error", detail=str(e)), 500


@api_bp.route("/report", methods=["GET", "POST"])
@cross_origin(origins="*")
def report_root():
    _ensure_aux_tables()
    nid = _require_id_arg()
    if isinstance(nid, Response):
        return nid
    # compute reporter fingerprint (ip+ua)
    ip = (request.headers.get("X-Forwarded-For", "").split(",")[0].strip() or (request.remote_addr or ""))
    ua = request.headers.get("User-Agent", "")
    fp = f"{ip}|{ua}"
    try:
        with db.session.begin():
            # ensure note exists
            row = db.session.execute(text("SELECT 1 FROM notes WHERE id=:id"), {"id": nid}).first()
            if not row:
                return jsonify(error="not_found"), 404
            db.session.execute(text(
                "INSERT INTO note_reports(note_id, fp) VALUES (:nid, :fp) ON CONFLICT DO NOTHING"
            ), {"nid": nid, "fp": fp})
            # bump visible reports counter
            res = db.session.execute(text(
                "UPDATE notes SET reports=COALESCE(reports,0)+1 WHERE id=:id RETURNING reports"
            ), {"id": nid}).first()
            reports_val = int(res[0]) if res else 0
            # count distinct reporters
            distinct = db.session.execute(text(
                "SELECT COUNT(*) FROM note_reports WHERE note_id=:nid"
            ), {"nid": nid}).scalar() or 0
            if distinct >= 3:
                db.session.execute(text("DELETE FROM notes WHERE id=:id"), {"id": nid})
                return jsonify(ok=True, id=nid, status="deleted", reports=reports_val), 200
        return jsonify(ok=True, id=nid, status="pending", reports=reports_val), 200
    except Exception as e:
        current_app.logger.exception("report root failed")
        return jsonify(error="db_error", detail=str(e)), 500
