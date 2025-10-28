from flask import Blueprint, jsonify, request
from datetime import date, datetime, timezone
from sqlalchemy import text as _text
import sqlalchemy as sa
import random
import time
from . import limiter
from .utils.db import retry_with_backoff, advisory_lock_for
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

def _is_transient_db_error(exc: Exception) -> bool:
    msg = (str(getattr(exc, "orig", exc)) or "").lower()
    return (
        "deadlock" in msg
        or "could not serialize" in msg
        or "serialization failure" in msg
        or "database is locked" in msg
        or "lock timeout" in msg
        or ("timeout" in msg and "statement" in msg)
    )

def _retry_on_transient_errors(fn, attempts: int = 5, base_delay: float = 0.05):
    last = None
    for i in range(1, attempts + 1):
        try:
            return fn()
        except Exception as exc:
            last = exc
            if not _is_transient_db_error(exc) or i >= attempts:
                break
            time.sleep(min(1.0, base_delay * (2 ** (i - 1)) + random.uniform(0, base_delay)))
    if last:
        raise last

def _dialect_name(conn) -> str:
    try:
        return getattr(conn, "engine").dialect.name
    except Exception:
        return "unknown"

def _insert_ignore(conn, table, cols, values, conflict=None) -> bool:
    cols_list = ", ".join(cols)
    ph = ", ".join(f":{c}" for c in cols)
    dname = _dialect_name(conn)
    if dname.startswith("sqlite"):
        sql = f"INSERT OR IGNORE INTO {table}({cols_list}) VALUES({ph})"
    else:
        if conflict:
            conflict_cols = ", ".join(conflict)
            sql = f"INSERT INTO {table}({cols_list}) VALUES({ph}) ON CONFLICT({conflict_cols}) DO NOTHING"
        else:
            sql = f"INSERT INTO {table}({cols_list}) VALUES({ph})"
    res = conn.execute(sa.text(sql), values)
    return res.rowcount > 0

@api_bp.route("/view", methods=["GET", "POST"])
@limiter.limit("60 per minute")
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
        def _tx():
            with db.engine.begin() as cx:  # type: ignore[attr-defined]
                # Optional per-note advisory lock (Postgres only; env-gated)
                with advisory_lock_for(cx, note_id):
                    inserted = _insert_ignore(
                        cx,
                        "view_log",
                        ["note_id", "fingerprint", "day", "created_at"],
                        {"note_id": note_id, "fingerprint": fp, "day": day, "created_at": now},
                        conflict=["note_id", "fingerprint", "day"],
                    )
                    if inserted:
                        cx.execute(_text("UPDATE notes SET views = COALESCE(views,0) + 1 WHERE id=:id"), {"id": note_id})
                    row = cx.execute(_text("SELECT id, COALESCE(views,0) AS views FROM notes WHERE id=:id"), {"id": note_id}).first()
                    if not row:
                        raise LookupError("not_found")
                    return jsonify(ok=True, id=row.id, views=row.views), 200

        return retry_with_backoff(_tx, attempts=5, base_delay=0.05)
    except LookupError:
        return jsonify(ok=False, error="not_found"), 404
    except Exception as exc:
        msg = (str(getattr(exc, "orig", exc)) or "").lower()
        if "database is locked" in msg or "deadlock" in msg or "timeout" in msg or "could not serialize" in msg:
            return jsonify(ok=False, error="db_busy"), 503
        return jsonify(ok=False, error="server_error"), 500
