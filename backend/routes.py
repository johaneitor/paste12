from flask import Blueprint, jsonify, request
from datetime import date, datetime, timezone
from sqlalchemy import text as _text
from . import limiter
from . import db

# Nota: Este blueprint se registra con url_prefix="/api" en create_app().
# Por lo tanto, la ruta efectiva es /api/view
api_bp = Blueprint("api", __name__)

def _today_iso() -> str:
    return date.today().isoformat()

def _now():
    return datetime.now(timezone.utc)

def _fingerprint(req) -> str:
    try:
        # headers priorizadas; fallback a IP+UA
        fp = (
            req.headers.get("X-Author-Fp")
            or req.headers.get("X-Fingerprint")
            or req.cookies.get("fp")
        )
        if fp:
            return fp
        base = f"{req.remote_addr}|{req.user_agent.string}"
        import hashlib
        return hashlib.sha256(base.encode("utf-8")).hexdigest()[:32]
    except Exception:
        return "anon"

@api_bp.route("/view", methods=["GET", "POST"])
@limiter.limit("60 per hour")
def view_alias():
    """
    Alias de compatibilidad para clientes antiguos: /api/view?id=<id>
    - GET: no permitido (404) para evitar efectos laterales con GET.
    - POST: idempotente por (note_id, fp, day). Incrementa views en notes.
    """
    if request.method == "GET":
        return jsonify(error="not_found"), 404

    raw = request.args.get("id") or request.form.get("id")
    try:
        note_id = int(raw)
    except Exception:
        return jsonify(error="bad_id"), 404

    fp = _fingerprint(request)
    day = _today_iso()
    now = _now()

    try:
        with db.engine.begin() as cx:  # type: ignore[attr-defined]
            cx.execute(_text(
                """
                CREATE TABLE IF NOT EXISTS view_log(
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  note_id INTEGER NOT NULL,
                  fingerprint VARCHAR(128) NOT NULL,
                  day TEXT NOT NULL,
                  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                  UNIQUE(note_id, fingerprint, day)
                )
                """
            ))
            inserted = cx.execute(_text(
                """
                INSERT OR IGNORE INTO view_log(note_id,fingerprint,day,created_at)
                VALUES(:note_id,:fp,:day,:now)
                """
            ), {"note_id": note_id, "fp": fp, "day": day, "now": now}).rowcount > 0

            if inserted:
                cx.execute(_text("UPDATE notes SET views = COALESCE(views,0) + 1 WHERE id=:id"), {"id": note_id})

            row = cx.execute(_text("SELECT id, COALESCE(views,0) AS views FROM notes WHERE id=:id"), {"id": note_id}).first()
            if not row:
                return jsonify(ok=False, error="not_found"), 404
            return jsonify(ok=True, id=row.id, views=row.views), 200
    except Exception as exc:
        return jsonify(ok=False, error="server_error"), 500
