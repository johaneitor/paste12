from __future__ import annotations
from datetime import datetime, timezone, date
import hashlib, os

def _engine():
    from sqlalchemy import create_engine
    # Align default with backend factory (sqlite under /tmp)
    url = (
        os.environ.get("SQLALCHEMY_DATABASE_URI")
        or os.environ.get("DATABASE_URL")
        or "sqlite:////tmp/paste12.db"
    )
    # Normalize legacy postgres://
    if url.startswith("postgres://"):
        url = url.replace("postgres://", "postgresql://", 1)
    return create_engine(url, pool_pre_ping=True)

def _dialect(conn):
    # SQLAlchemy 2.0 Connection exposes .engine
    return getattr(conn, "engine").dialect.name

def _now():
    return datetime.now(timezone.utc)

def _get_fp(request):
    # Prioriza cabeceras/cookie; fallback a hash(IP+UA)
    fp = (
        request.headers.get("X-Author-Fp")
        or request.headers.get("X-Fingerprint")
        or request.cookies.get("fp")
    )
    if not fp:
        base = f"{request.remote_addr}|{request.user_agent.string}"
        fp = hashlib.sha256(base.encode("utf-8")).hexdigest()[:32]
    return fp

def register_into(app):
    """
    Registra:
      POST /api/notes/<id>/like   -> idempotente por (note_id, fp)
      POST /api/notes/<id>/view   -> incrementa vistas (cliente ya evita repetir)
      POST /api/notes/<id>/report -> idempotente por (note_id, fp); si >= threshold, borra nota
    """
    from flask import request, jsonify
    import sqlalchemy as sa

    THRESHOLD = int(os.environ.get("REPORT_THRESHOLD", "5") or "5")

    def _insert_ignore(conn, table, cols, values, conflict=None):
        """
        Inserta ignorando duplicados, tanto en sqlite como en postgres.
        conflict: columnas de conflicto (solo para postgres)
        """
        dialect = _dialect(conn)
        cols_list = ", ".join(cols)
        ph = ", ".join(f":{c}" for c in cols)
        if dialect.startswith("sqlite"):
            sql = f"INSERT OR IGNORE INTO {table}({cols_list}) VALUES({ph})"
        else:
            if conflict:
                conflict_cols = ", ".join(conflict)
                sql = f"INSERT INTO {table}({cols_list}) VALUES({ph}) ON CONFLICT({conflict_cols}) DO NOTHING"
            else:
                sql = f"INSERT INTO {table}({cols_list}) VALUES({ph})"
        res = conn.execute(sa.text(sql), values)
        return res.rowcount > 0

    @app.post("/api/notes/<int:note_id>/like")
    def like_note(note_id: int):
        fp = _get_fp(request)
        now = _now()
        with _engine().begin() as cx:
            # Asegura tablas mínimas si faltan (no rompe si existen)
            cx.execute(sa.text("""
                CREATE TABLE IF NOT EXISTS like_log(
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  note_id INTEGER NOT NULL,
                  fingerprint VARCHAR(128) NOT NULL,
                  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                  UNIQUE(note_id, fingerprint)
                )
            """))
            # Log idempotente
            inserted = _insert_ignore(
                cx,
                "like_log",
                ["note_id","fingerprint","created_at"],
                {"note_id": note_id, "fingerprint": fp, "created_at": now},
                conflict=["note_id","fingerprint"],
            )
            if inserted:
                cx.execute(sa.text("UPDATE notes SET likes = COALESCE(likes,0) + 1 WHERE id=:id"), {"id": note_id})
            row = cx.execute(sa.text("SELECT id, COALESCE(likes,0) AS likes FROM notes WHERE id=:id"), {"id": note_id}).first()
            if not row:
                return jsonify(ok=False, error="not_found"), 404
            return jsonify(ok=True, id=row.id, likes=row.likes), 200

    @app.post("/api/notes/<int:note_id>/view")
    def view_note(note_id: int):
        fp = _get_fp(request)
        today = date.today().isoformat()
        now = _now()
        with _engine().begin() as cx:
            cx.execute(sa.text("""
                CREATE TABLE IF NOT EXISTS view_log(
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  note_id INTEGER NOT NULL,
                  fingerprint VARCHAR(128) NOT NULL,
                  day TEXT NOT NULL,
                  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                  UNIQUE(note_id, fingerprint, day)
                )
            """))
            # Intento idempotente por (note_id, fp, day)
            inserted = _insert_ignore(
                cx,
                "view_log",
                ["note_id","fingerprint","day","created_at"],
                {"note_id": note_id, "fingerprint": fp, "day": today, "created_at": now},
                conflict=["note_id","fingerprint","day"],
            )
            if inserted:
                cx.execute(sa.text("UPDATE notes SET views = COALESCE(views,0) + 1 WHERE id=:id"), {"id": note_id})
            row = cx.execute(sa.text("SELECT id, COALESCE(views,0) AS views FROM notes WHERE id=:id"), {"id": note_id}).first()
            if not row:
                return jsonify(ok=False, error="not_found"), 404
            return jsonify(ok=True, id=row.id, views=row.views), 200

    @app.post("/api/notes/<int:note_id>/report")
    def report_note(note_id: int):
        fp = _get_fp(request)
        reason = (request.json or {}).get("reason") if request.is_json else (request.form.get("reason") if request.form else None)
        now = _now()
        with _engine().begin() as cx:
            cx.execute(sa.text("""
                CREATE TABLE IF NOT EXISTS report_log(
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  note_id INTEGER NOT NULL,
                  fingerprint VARCHAR(128) NOT NULL,
                  reason TEXT,
                  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                  UNIQUE(note_id, fingerprint)
                )
            """))
            inserted = _insert_ignore(
                cx,
                "report_log",
                ["note_id","fingerprint","reason","created_at"],
                {"note_id": note_id, "fingerprint": fp, "reason": reason, "created_at": now},
                conflict=["note_id","fingerprint"],
            )
            if inserted:
                cx.execute(sa.text("UPDATE notes SET reports = COALESCE(reports,0) + 1 WHERE id=:id"), {"id": note_id})
            # Chequear total reportes
            total = cx.execute(sa.text("SELECT COALESCE(reports,0) FROM notes WHERE id=:id"), {"id": note_id}).scalar() or 0
            removed = False
            if total >= THRESHOLD:
                cx.execute(sa.text("DELETE FROM notes WHERE id=:id"), {"id": note_id})
                removed = True
            return jsonify(ok=True, id=note_id, reports=total, removed=removed), 200

def register_alias_into(app):
    # Hoy no hay alias extra; dejamos el nombre expuesto porque el wsgi-bridge lo llama.
    return register_into(app)
