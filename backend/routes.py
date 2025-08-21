from __future__ import annotations

import os
os.environ.setdefault("ENABLE_VIEWS","1")
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

def _real_ip():
    h = request.headers
    xff = (h.get("X-Forwarded-For") or "").strip()
    if xff:
        return xff.split(",")[0].strip()
    cip = h.get("CF-Connecting-IP")
    if cip:
        return cip.strip()
    return request.remote_addr or "anon"

def _views_enabled():
    import os
    # por defecto on (1). Sólo se apaga con ENABLE_VIEWS="0"
    return (os.getenv("ENABLE_VIEWS","1") != "0")

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
    # Vista única por fingerprint y día (UTC). Postgres: ON CONFLICT DO NOTHING.
    from flask import jsonify, current_app
    import os
    from sqlalchemy import text
    n = Note.query.get_or_404(note_id)

    # Si alguien dejó un kill-switch, lo ignoramos salvo que esté explícitamente en "0"
    if not _views_enabled():
        return jsonify({"counted": False, "views": int(n.views or 0), "disabled": True})

    fp = _fp() or "anon"
    today = _now().date()
    counted = False
    try:
        dialect = db.session.bind.dialect.name

        if dialect == "postgresql":
            # Intento de inserción idempotente por (note_id, fp, view_date)
            row = db.session.execute(text("""
                INSERT INTO view_log (note_id, fingerprint, view_date, created_at)
                VALUES (:nid, :fp, :vd, (NOW() AT TIME ZONE 'UTC'))
                ON CONFLICT (note_id, fingerprint, view_date) DO NOTHING
                RETURNING id
            """), {"nid": note_id, "fp": fp, "vd": today}).first()

            if row:
                db.session.execute(text("UPDATE note SET views = COALESCE(views,0)+1 WHERE id=:nid"),
                                   {"nid": note_id})
                counted = True

            # Leer valor actual para responder
            v = db.session.execute(text("SELECT COALESCE(views,0) FROM note WHERE id=:nid"),
                                   {"nid": note_id}).scalar() or 0
            db.session.commit()
            return jsonify({"counted": counted, "views": int(v)})

        else:
            # SQLite/u otros: ORM + UNIQUE (note_id, fp, view_date) maneja duplicados
            try:
                db.session.add(ViewLog(note_id=note_id, fingerprint=fp, view_date=today))
                db.session.flush()
                n.views = int(n.views or 0) + 1
                counted = True
                db.session.commit()
            except IntegrityError:
                db.session.rollback()
            return jsonify({"counted": counted, "views": int(n.views or 0)})

    except Exception as e:
        # Log detallado y 500 para detectar esquemas rotos
        current_app.logger.exception("view_note error: %s", e)
        db.session.rollback()
        return jsonify({"ok": False, "error": "view insert failed"}), 500

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


@bp.get("/admin/diag_views")
def diag_views():
    # requiere token admin por header
    if request.headers.get("X-Admin-Token") != (os.getenv("ADMIN_TOKEN","changeme")):
        return jsonify({"ok": False, "error": "unauthorized"}), 401
    try:
        note_id = int(request.args.get("note_id","0"))
    except Exception:
        return jsonify({"ok": False, "error": "note_id required"}), 400
    today = _now().date()
    rows = db.session.execute(
        db.text("SELECT note_id,fingerprint,view_date FROM view_log WHERE note_id=:nid AND view_date=:vd ORDER BY fingerprint LIMIT 50"),
        {"nid": note_id, "vd": today}
    ).mappings().all()
    return jsonify({"ok": True, "today": str(today), "count": len(rows), "rows": list(rows)}), 200


@bp.post("/admin/fix_viewlog_uniques")
def admin_fix_viewlog_uniques():
    """
    - Requiere X-Admin-Token == ADMIN_TOKEN (por defecto 'changeme')
    - Postgres: elimina cualquier UNIQUE/índice único sobre (note_id,fingerprint) que NO incluya view_date.
    - Asegura:
        * columna view_date
        * UNIQUE (note_id,fingerprint,view_date)
        * índices ix_view_log_note_id, ix_view_log_view_date
    """
    import os
    from sqlalchemy import text
    tok = request.headers.get("X-Admin-Token") or ""
    expected = os.getenv("ADMIN_TOKEN") or "changeme"
    if tok != expected:
        return jsonify({"ok": False, "error": "unauthorized"}), 401

    out = {"ok": True, "dialect": db.session.bind.dialect.name, "dropped": [], "created": [], "info": []}
    dialect = out["dialect"]

    def info(msg): out["info"].append(msg)

    # 0) columna view_date idempotente
    if dialect == "postgresql":
        db.session.execute(text("ALTER TABLE view_log ADD COLUMN IF NOT EXISTS view_date date"))
        db.session.execute(text("UPDATE view_log SET view_date = (created_at AT TIME ZONE 'UTC')::date WHERE view_date IS NULL"))
        info("view_date ensured/backfilled (pg)")
    else:
        try:
            db.session.execute(text("ALTER TABLE view_log ADD COLUMN view_date DATE"))
        except Exception:
            pass
        db.session.execute(text("UPDATE view_log SET view_date = date(created_at) WHERE view_date IS NULL"))
        info("view_date ensured/backfilled (sqlite/other)")

    if dialect == "postgresql":
        # 1) buscar constraints únicos sobre view_log
        cons = db.session.execute(text("""
            SELECT conname, pg_get_constraintdef(c.oid) AS def
            FROM pg_constraint c
            JOIN pg_class t ON c.conrelid=t.oid
            WHERE t.relname='view_log' AND c.contype='u'
        """)).mappings().all()

        # dropear los que sean EXACTAMENTE únicos sobre (note_id, fingerprint) sin view_date
        for row in cons:
            name = row["conname"]
            defi = (row["def"] or "").lower()
            # ejemplo de def: 'UNIQUE (note_id, fingerprint)'
            if "unique" in defi and "view_date" not in defi:
                # comprobamos que solo estén note_id y fingerprint
                cols = defi.split("(")[1].split(")")[0].replace(" ", "")
                if cols in {"note_id,fingerprint", '"note_id","fingerprint"'}:
                    db.session.execute(text(f'ALTER TABLE view_log DROP CONSTRAINT "{name}"'))
                    out["dropped"].append(f'constraint:{name}')

        # 2) buscar índices únicos
        idxs = db.session.execute(text("""
            SELECT indexname, indexdef
            FROM pg_indexes
            WHERE tablename='view_log'
        """)).mappings().all()
        for row in idxs:
            name = row["indexname"]
            defi = (row["indexdef"] or "").lower()
            # ejemplo: 'CREATE UNIQUE INDEX ... ON public.view_log USING btree (note_id, fingerprint)'
            if "unique index" in defi and "view_date" not in defi:
                # columnas entre paréntesis
                try:
                    cols = defi.split("(")[1].split(")")[0].replace(" ", "")
                except Exception:
                    cols = ""
                if cols in {"note_id,fingerprint", '"note_id","fingerprint"'}:
                    db.session.execute(text(f'DROP INDEX IF EXISTS "{name}"'))
                    out["dropped"].append(f'index:{name}')

        # 3) asegurar UNIQUE correcto (note_id,fingerprint,view_date)
        exists = db.session.execute(text("""
            SELECT conname
            FROM pg_constraint
            WHERE conrelid='view_log'::regclass AND contype='u'
              AND pg_get_constraintdef(oid) ILIKE '%unique%view_date%'
        """)).first()
        if not exists:
            db.session.execute(text('ALTER TABLE view_log ADD CONSTRAINT "uq_view_note_fp_day" UNIQUE (note_id, fingerprint, view_date)'))
            out["created"].append('constraint:uq_view_note_fp_day')

        # 4) índices
        db.session.execute(text("CREATE INDEX IF NOT EXISTS ix_view_log_note_id ON view_log (note_id)"))
        db.session.execute(text("CREATE INDEX IF NOT EXISTS ix_view_log_view_date ON view_log (view_date)"))
        out["created"] += ["index:ix_view_log_note_id", "index:ix_view_log_view_date"]

    else:
        # sqlite: índice único de 3 columnas
        db.session.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS uq_view_note_fp_day ON view_log(note_id, fingerprint, view_date)"))
        db.session.execute(text("CREATE INDEX IF NOT EXISTS ix_view_log_note_id ON view_log (note_id)"))
        db.session.execute(text("CREATE INDEX IF NOT EXISTS ix_view_log_view_date ON view_log (view_date)"))
        out["created"] += ["index:uq_view_note_fp_day","index:ix_view_log_note_id","index:ix_view_log_view_date"]

    db.session.commit()
    return jsonify(out), 200



@bp.get("/admin/diag_viewlog_rows")
def admin_diag_viewlog_rows():
    import os
    if request.headers.get("X-Admin-Token") != (os.getenv("ADMIN_TOKEN","changeme")):
        return jsonify({"ok": False, "error": "unauthorized"}), 401
    try:
        note_id = int(request.args.get("note_id","0"))
    except Exception:
        return jsonify({"ok": False, "error": "note_id required"}), 400
    fp = request.args.get("fp")
    q = "SELECT id,note_id,fingerprint,view_date,created_at FROM view_log WHERE note_id=:nid"
    params = {"nid": note_id}
    if fp:
        q += " AND fingerprint=:fp"
        params["fp"] = fp
    q += " ORDER BY created_at DESC LIMIT 100"
    rows = db.session.execute(db.text(q), params).mappings().all()
    return jsonify({"ok": True, "count": len(rows), "rows": list(rows)}), 200
