from __future__ import annotations
import hashlib, os
from datetime import datetime, timedelta
from flask import Blueprint, jsonify, request
from backend import limiter

def _now(): 
    return datetime.utcnow()

def _fp(req) -> str:
    ip = req.headers.get("X-Forwarded-For","") or req.headers.get("CF-Connecting-IP","") or (req.remote_addr or "")
    ua = req.headers.get("User-Agent","")
    salt = os.environ.get("FP_SALT","")
    return hashlib.sha256(f"{ip}|{ua}|{salt}".encode()).hexdigest()[:32]

def _has_rule(app, rule: str, method: str) -> bool:
    try:
        for r in app.url_map.iter_rules():
            if str(r) == rule and method.upper() in r.methods:
                return True
    except Exception as exc:
        app.logger.debug("[routes_notes] has_rule failed: %r", exc)
    return False

def register_api(app):
    """
    Registra /api/notes GET y POST si no existen aún. Idempotente.
    Requiere backend.models.Note y backend.db ya inicializados por create_app().
    """
    if _has_rule(app, "/api/notes", "GET") and _has_rule(app, "/api/notes", "POST"):
        return "present"

    from backend import db
    from backend.models import Note  # debe existir el modelo con author_fp

    api_bp = Blueprint("api_notes_capsule", __name__)

    @api_bp.get("/notes")
    @limiter.limit("60/minute")
    def list_notes():
        """
        Lista notas con compatibilidad incremental:
        - Soporta paginación por cursor via before_id (id descendente).
        - "limit" (1..100), default 20.
        - "active_only=1" oculta eliminadas/expiradas (si hay TTL).
        - "wrap=1" devuelve {items, has_more, next_before_id}; sin wrap → array crudo.
        Además, si hay siguiente página, agrega Link: <...>; rel="next".
        """
        try:
            try:
                limit = int(request.args.get("limit", 20) or 20)
            except Exception:
                limit = 20
            limit = max(1, min(100, limit))

            before_id_raw = request.args.get("before_id")
            before_id = int(before_id_raw) if before_id_raw and before_id_raw.isdigit() else None

            wrap = (request.args.get("wrap") or "").lower() in ("1", "true", "yes", "on")
            active_only = (request.args.get("active_only") or "").lower() in ("1", "true", "yes", "on")

            q = Note.query
            if active_only:
                try:
                    q = q.filter((Note.deleted_at.is_(None)))
                except Exception:
                    pass
            if before_id:
                q = q.filter(Note.id < before_id)
            q = q.order_by(Note.id.desc())
            rows = q.limit(limit).all()

            now = _now()
            items = [
                {
                    "id": n.id,
                    "text": n.text,
                    "timestamp": (n.timestamp or now).isoformat(),
                    "expires_at": (n.expires_at.isoformat() if n.expires_at else None),
                    "likes": n.likes,
                    "views": n.views,
                    "reports": n.reports,
                    "author_fp": getattr(n, "author_fp", None),
                }
                for n in rows
            ]

            has_more = len(items) >= limit
            next_before_id = (items[-1]["id"] if has_more else None)

            resp_body = ( {"items": items, "has_more": has_more, "next_before_id": next_before_id} if wrap else items )
            resp = jsonify(resp_body)

            # Link header para la siguiente página
            if has_more and next_before_id:
                try:
                    base = (request.url_root or "").rstrip("/")
                    nxt = f"{base}/api/notes?limit={limit}&before_id={next_before_id}"
                    resp.headers["Link"] = f"<{nxt}>; rel=\"next\""
                except Exception:
                    pass
            return resp, 200
        except Exception as exc:
            return jsonify(error="server_error"), 500

    @api_bp.post("/notes")
    @limiter.limit("1 per 10 seconds")
    @limiter.limit("500 per day")
    def create_note():
        """Crea una nota. Acepta JSON o x-www-form-urlencoded.
        Reconoce "ttl_hours" (canónico) o "hours" (legacy).
        """
        data = {}
        if request.is_json:
            data = request.get_json(silent=True) or {}
        else:
            try:
                data = {k: v for k, v in (request.form or {}).items()}
            except Exception:
                data = {}

        text = (data.get("text") or "").strip()
        if not text:
            return jsonify(error="text required"), 400

        # TTL: preferir ttl_hours; fallback a hours; default Note.default_ttl_hours()
        ttl_raw = data.get("ttl_hours") or data.get("hours") or Note.default_ttl_hours()
        try:
            hours = int(ttl_raw)
        except Exception:
            hours = Note.default_ttl_hours()
        hours = min(168, max(1, hours))

        now = _now()
        n = Note(
            text=text,
            timestamp=now,
            expires_at=now + timedelta(hours=hours),
            author_fp=_fp(request),
        )
        db.session.add(n)
        db.session.commit()
        return jsonify({
            "id": n.id,
            "text": n.text,
            "timestamp": n.timestamp.isoformat(),
            "expires_at": n.expires_at.isoformat() if n.expires_at else None,
            "likes": n.likes,
            "views": n.views,
            "reports": n.reports,
            "author_fp": getattr(n, "author_fp", None),
        }), 201

    app.register_blueprint(api_bp, url_prefix="/api")
    return "registered"
