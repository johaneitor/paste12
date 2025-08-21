from __future__ import annotations

import os
from datetime import datetime, timezone, timedelta
from typing import Optional

from flask import Blueprint, current_app, jsonify, request
from sqlalchemy.exc import IntegrityError
from werkzeug.exceptions import HTTPException, MethodNotAllowed, NotFound, BadRequest

from . import db, limiter
from .models import Note, LikeLog, ReportLog, ViewLog

# Blueprint único (se registra en create_app con url_prefix="/api")
bp = Blueprint("api", __name__)

# ===== Helpers =====
def _now() -> datetime:
    return datetime.now(timezone.utc)

def _aware(dt: Optional[datetime]) -> Optional[datetime]:
    if dt is None:
        return None
    return dt if getattr(dt, "tzinfo", None) else dt.replace(tzinfo=timezone.utc)

def _fp() -> str:
    return (
        request.headers.get("X-Client-Fingerprint")
        or request.headers.get("X-User-Token")
        or request.cookies.get("p12_fp")
        or request.headers.get("CF-Connecting-IP")
        or (request.headers.get("X-Forwarded-For") or "").split(",")[0].strip()
        or request.cookies.get("fp")
        or request.remote_addr
        or "anon"
    )

def _rate_key() -> str:
    return _fp()

def _per_page() -> int:
    try:
        v = int(os.getenv("PAGE_SIZE", "15"))
    except Exception:
        v = 15
    if v < 10:
        v = 10
    if v > 100:
        v = 100
    return v

def _note_json(n: Note, now: Optional[datetime] = None) -> dict:
    now = _aware(now) or _now()
    ts = _aware(getattr(n, "timestamp", None))
    exp = _aware(getattr(n, "expires_at", None))
    remaining = max(0, int((exp - now).total_seconds())) if exp else None
    return {
        "id": n.id,
        "text": n.text,
        "timestamp": ts.isoformat() if ts else None,
        "expires_at": exp.isoformat() if exp else None,
        "remaining": remaining,
        "likes": int(n.likes or 0),
        "views": int(n.views or 0),
        "reports": int(n.reports or 0),
    }

# ===== Error handler JSON a nivel app (cubre 500 con HTML) =====
@bp.app_errorhandler(Exception)
def _api_error(e):
    try:
        current_app.logger.exception("API error: %s", e)
    except Exception:
        pass
    return jsonify({"ok": False, "error": str(e)}), 500

# ===== Endpoints =====
@bp.get("/health")
def health():
    return jsonify({"ok": True, "now": _now().isoformat()}), 200

@bp.get("/notes")
def list_notes():
    try:
        now = _now()
        try:
            page = int(request.args.get("page", "1"))
        except Exception:
            page = 1
        if page < 1:
            page = 1
        page_size = _per_page()
        q = Note.query.filter(Note.expires_at > now).order_by(Note.timestamp.desc())
        items = q.offset((page - 1) * page_size).limit(page_size).all()
        has_more = len(items) == page_size
        return jsonify({
            "page": page,
            "page_size": page_size,
            "has_more": has_more,
            "notes": [_note_json(n, now) for n in items],
        })
    except Exception as e:
        current_app.logger.exception("list_notes failed: %s", e)
        return jsonify({"ok": False, "error": str(e)}), 500

@bp.post("/notes")
@limiter.limit("1 per 10 seconds", key_func=_rate_key)
@limiter.limit("10 per day", key_func=_rate_key)  # 10/día por usuario (fingerprint)
def create_note():
    data = request.get_json(silent=True) or {}
    text = (data.get("text") or "").strip()
    if not text:
        return jsonify({"error": "text is required"}), 400
    try:
        hours = int(data.get("hours", 12))
    except Exception:
        hours = 12
    hours = min(168, max(1, hours))
    now = _now()
    n = Note(text=text, timestamp=now, expires_at=now + timedelta(hours=hours))
    db.session.add(n)
    db.session.commit()
    return jsonify(_note_json(n, now)), 201

@bp.post("/notes/<int:note_id>/like")
def like_note(note_id: int):
    n = Note.query.get_or_404(note_id)
    fp = _fp()
    try:
        db.session.add(LikeLog(note_id=note_id, fingerprint=fp))
        db.session.flush()
        n.likes = int(n.likes or 0) + 1
        db.session.commit()
        return jsonify({"likes": int(n.likes or 0), "already_liked": False})
    except IntegrityError:
        db.session.rollback()
        return jsonify({"likes": int(n.likes or 0), "already_liked": True})

@bp.post("/notes/<int:note_id>/report")
def report_note(note_id: int):
    n = Note.query.get_or_404(note_id)
    fp = _fp()
    try:
        db.session.add(ReportLog(note_id=note_id, fingerprint=fp))
        db.session.flush()
        n.reports = int(n.reports or 0) + 1
        if n.reports >= 5:
            db.session.delete(n)
            db.session.commit()
            return jsonify({"deleted": True, "reports": 0, "already_reported": False})
        db.session.commit()
        return jsonify({"deleted": False, "reports": int(n.reports or 0), "already_reported": False})
    except IntegrityError:
        db.session.rollback()
        return jsonify({"deleted": False, "reports": int(n.reports or 0), "already_reported": True})

@bp.post("/notes/<int:note_id>/view")
def view_note(note_id: int):
    # Kill-switch para evitar locks de SQLite bajo carga
    if os.getenv("ENABLE_VIEWS", "1") != "1":
        n = Note.query.get_or_404(note_id)
        return jsonify({"views": int(n.views or 0), "counted": False})
    n = Note.query.get_or_404(note_id)
    fp = _fp()
    today = _now().date()
    counted = False
    try:
        db.session.add(ViewLog(note_id=note_id, fingerprint=fp, view_date=today))
        db.session.flush()
        n.views = int(n.views or 0) + 1
        db.session.commit()
        counted = True
    except IntegrityError:
        db.session.rollback()
    return jsonify({"views": int(n.views or 0), "counted": counted})


# --- Generic JSON error handler that preserves HTTP status ---
@bp.errorhandler(Exception)
def __api_error_handler(e):
    from flask import current_app, jsonify
    try:
        if isinstance(e, HTTPException):
            return jsonify({"ok": False, "error": e.description}), e.code
        current_app.logger.exception("API error: %s", e)
        return jsonify({"ok": False, "error": str(e)}), 500
    except Exception:  # fallback
        return ("", 500)


@bp.post("/notes/report")
def __report_missing():
    from flask import jsonify
    return jsonify({"ok": False, "error": "note_id required"}), 400

@bp.post("/notes/like")
def __like_missing():
    from flask import jsonify
    return jsonify({"ok": False, "error": "note_id required"}), 400

@bp.post("/notes/view")
def __view_missing():
    from flask import jsonify
    return jsonify({"ok": False, "error": "note_id required"}), 400

# --- Admin: asegurar esquema de ViewLog en producción (usa la DB ya conectada) ---
@bp.post("/admin/ensure_viewlog")
def admin_ensure_viewlog():
    import os
    from sqlalchemy import text
    tok = request.headers.get("X-Admin-Token") or ""
    expected = os.getenv("ADMIN_TOKEN") or "changeme"
    if tok != expected:
        return jsonify({"ok": False, "error": "unauthorized"}), 401

    dialect = db.session.bind.dialect.name
    out = {"dialect": dialect, "steps": []}
    def step(s): out["steps"].append(s)
    try:
        if dialect == "postgresql":
            db.session.execute(text("ALTER TABLE view_log ADD COLUMN IF NOT EXISTS view_date date"))
            step("ADD COLUMN view_date (pg)")
            db.session.execute(text("UPDATE view_log SET view_date = (created_at AT TIME ZONE 'UTC')::date WHERE view_date IS NULL"))
            step("BACKFILL view_date")
            # eliminar UNIQUE antiguo si existiera
            try:
                db.session.execute(text('ALTER TABLE view_log DROP CONSTRAINT "uq_view_note_fp"'))
                step("DROP UNIQUE uq_view_note_fp")
            except Exception:
                pass
            # crear UNIQUE nuevo (nota+fp+día)
            try:
                db.session.execute(text('ALTER TABLE view_log ADD CONSTRAINT "uq_view_note_fp_day" UNIQUE (note_id, fingerprint, view_date)'))
                step("ADD UNIQUE uq_view_note_fp_day")
            except Exception:
                step("UNIQUE uq_view_note_fp_day exists")
        else:
            db.session.execute(text("ALTER TABLE view_log ADD COLUMN view_date DATE"))
            step("ADD COLUMN view_date (sqlite)")
            db.session.execute(text("UPDATE view_log SET view_date = date(created_at) WHERE view_date IS NULL"))
            step("BACKFILL view_date (sqlite)")
            db.session.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS uq_view_note_fp_day ON view_log(note_id, fingerprint, view_date)"))
            step("CREATE UNIQUE INDEX uq_view_note_fp_day (sqlite)")

        db.session.execute(text("CREATE INDEX IF NOT EXISTS ix_view_log_note_id ON view_log (note_id)"))
        db.session.execute(text("CREATE INDEX IF NOT EXISTS ix_view_log_view_date ON view_log (view_date)"))
        db.session.commit()
        return jsonify({"ok": True, **out})
    except Exception as e:
        db.session.rollback()
        return jsonify({"ok": False, "error": str(e), **out}), 500

# --- Admin: asegurar esquema de ViewLog (usa db.engine.begin) ---
@bp.post("/admin/ensure_viewlog_fix")
def admin_ensure_viewlog_fix():
    import os
    from sqlalchemy import text

    tok = request.headers.get("X-Admin-Token") or ""
    expected = os.getenv("ADMIN_TOKEN") or "changeme"
    if tok != expected:
        return jsonify({"ok": False, "error": "unauthorized"}), 401

    out = {"steps": []}
    try:
        # Usar engine directamente, no db.session.bind
        with db.engine.begin() as conn:
            dialect = conn.dialect.name
            out["dialect"] = dialect

            if dialect == "postgresql":
                conn.execute(text("ALTER TABLE view_log ADD COLUMN IF NOT EXISTS view_date date"))
                out["steps"].append("ADD COLUMN view_date (pg)")
                conn.execute(text("UPDATE view_log SET view_date = (created_at AT TIME ZONE 'UTC')::date WHERE view_date IS NULL"))
                out["steps"].append("BACKFILL view_date")
                # borrar UNIQUE viejo si existe
                try:
                    conn.execute(text('ALTER TABLE view_log DROP CONSTRAINT "uq_view_note_fp"'))
                    out["steps"].append("DROP UNIQUE uq_view_note_fp")
                except Exception:
                    pass
                # crear UNIQUE nuevo
                try:
                    conn.execute(text('ALTER TABLE view_log ADD CONSTRAINT "uq_view_note_fp_day" UNIQUE (note_id, fingerprint, view_date)'))
                    out["steps"].append("ADD UNIQUE uq_view_note_fp_day")
                except Exception:
                    out["steps"].append("UNIQUE uq_view_note_fp_day exists")
            else:
                # SQLite
                conn.execute(text("ALTER TABLE view_log ADD COLUMN view_date DATE"))
                out["steps"].append("ADD COLUMN view_date (sqlite)")
                conn.execute(text("UPDATE view_log SET view_date = date(created_at) WHERE view_date IS NULL"))
                out["steps"].append("BACKFILL view_date (sqlite)")
                conn.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS uq_view_note_fp_day ON view_log(note_id, fingerprint, view_date)"))
                out["steps"].append("CREATE UNIQUE INDEX uq_view_note_fp_day (sqlite)")

            # índices útiles
            conn.execute(text("CREATE INDEX IF NOT EXISTS ix_view_log_note_id ON view_log (note_id)"))
            conn.execute(text("CREATE INDEX IF NOT EXISTS ix_view_log_view_date ON view_log (view_date)"))

        return jsonify({"ok": True, **out})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e), **out}), 500

# --- Admin: migración robusta de ViewLog (PG/SQLite, transacciones separadas) ---
@bp.post("/admin/ensure_viewlog_fix2")
def admin_ensure_viewlog_fix2():
    import os
    from sqlalchemy import text

    tok = request.headers.get("X-Admin-Token") or ""
    expected = os.getenv("ADMIN_TOKEN") or "changeme"
    if tok != expected:
        return jsonify({"ok": False, "error": "unauthorized"}), 401

    out = {"steps": []}

    try:
        # Detectar dialecto con una conexión corta
        with db.engine.begin() as conn:
            dialect = conn.dialect.name
        out["dialect"] = dialect

        if dialect == "postgresql":
            # 1) Columna view_date (sin romper si ya existe)
            with db.engine.begin() as conn:
                conn.execute(text("ALTER TABLE view_log ADD COLUMN IF NOT EXISTS view_date date"))
                out["steps"].append("ADD COLUMN view_date (pg)")
            # 2) Backfill
            with db.engine.begin() as conn:
                conn.execute(text("UPDATE view_log SET view_date = (created_at AT TIME ZONE 'UTC')::date WHERE view_date IS NULL"))
                out["steps"].append("BACKFILL view_date")
            # 3) Drop UNIQUE viejo si existiera
            with db.engine.begin() as conn:
                conn.execute(text('ALTER TABLE view_log DROP CONSTRAINT IF EXISTS "uq_view_note_fp"'))
                out["steps"].append("DROP UNIQUE uq_view_note_fp IF EXISTS")
            # 4) Crear UNIQUE nuevo solo si no existe
            with db.engine.begin() as conn:
                exists = conn.execute(text("""
                    SELECT 1
                    FROM pg_constraint
                    WHERE conrelid = 'view_log'::regclass
                      AND conname = 'uq_view_note_fp_day'
                      AND contype='u'
                """)).first()
                if not exists:
                    conn.execute(text('ALTER TABLE view_log ADD CONSTRAINT "uq_view_note_fp_day" UNIQUE (note_id, fingerprint, view_date)'))
                    out["steps"].append("ADD UNIQUE uq_view_note_fp_day")
                else:
                    out["steps"].append("UNIQUE uq_view_note_fp_day exists")
            # 5) Índices (idempotentes)
            with db.engine.begin() as conn:
                conn.execute(text("CREATE INDEX IF NOT EXISTS ix_view_log_note_id ON view_log (note_id)"))
                conn.execute(text("CREATE INDEX IF NOT EXISTS ix_view_log_view_date ON view_log (view_date)"))
                out["steps"].append("INDEXES ensured")

        else:
            # SQLite
            with db.engine.begin() as conn:
                # ADD COLUMN en SQLite falla si ya existe; probamos lectura primero
                try:
                    conn.execute(text("SELECT view_date FROM view_log LIMIT 0"))
                    out["steps"].append("COLUMN view_date already present (sqlite)")
                except Exception:
                    conn.execute(text("ALTER TABLE view_log ADD COLUMN view_date DATE"))
                    out["steps"].append("ADD COLUMN view_date (sqlite)")
            with db.engine.begin() as conn:
                conn.execute(text("UPDATE view_log SET view_date = date(created_at) WHERE view_date IS NULL"))
                out["steps"].append("BACKFILL view_date (sqlite)")
            with db.engine.begin() as conn:
                conn.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS uq_view_note_fp_day ON view_log(note_id, fingerprint, view_date)"))
                conn.execute(text("CREATE INDEX IF NOT EXISTS ix_view_log_note_id ON view_log (note_id)"))
                conn.execute(text("CREATE INDEX IF NOT EXISTS ix_view_log_view_date ON view_log (view_date)"))
                out["steps"].append("INDEXES ensured (sqlite)")

        return jsonify({"ok": True, **out}), 200

    except Exception as e:
        return jsonify({"ok": False, "error": str(e), **out}), 500
