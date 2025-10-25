from __future__ import annotations
from datetime import datetime, timezone, date
import hashlib, os, sqlite3

def _engine():
    from sqlalchemy import create_engine, event
    from sqlalchemy.engine import Engine
    # Align default with backend factory (sqlite under /tmp)
    url = (
        os.environ.get("SQLALCHEMY_DATABASE_URI")
        or os.environ.get("DATABASE_URL")
        or "sqlite:////tmp/paste12.db"
    )
    # Normalize legacy postgres://
    if url.startswith("postgres://"):
        url = url.replace("postgres://", "postgresql://", 1)

    opts = {"pool_pre_ping": True}
    try:
        if url.startswith("postgresql"):
            opts.update({"pool_size": 10, "max_overflow": 20, "pool_recycle": 280})
        elif url.startswith("sqlite"):
            # Reduce lock errors under light concurrency
            opts.update({"connect_args": {"timeout": 5.0}})
    except Exception:
        pass

    eng = create_engine(url, **opts)

    # Ensure SQLite pragmas on this engine (idempotent; safe no-op for others)
    @event.listens_for(Engine, "connect")
    def _sqlite_pragmas_on_connect(dbapi_conn, _):  # type: ignore[override]
        try:
            if isinstance(dbapi_conn, sqlite3.Connection):
                cur = dbapi_conn.cursor()
                try: cur.execute("PRAGMA journal_mode=WAL")
                except Exception: pass
                try: cur.execute("PRAGMA busy_timeout=5000")
                except Exception: pass
                try: cur.execute("PRAGMA synchronous=NORMAL")
                except Exception: pass
                cur.close()
        except Exception:
            pass

    return eng

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
        try:
            with _engine().begin() as cx:
                # Asegura tablas mínimas si faltan (dialecto-agnóstico)
                cx.execute(sa.text("""
                    CREATE TABLE IF NOT EXISTS like_log(
                      note_id INTEGER NOT NULL,
                      fingerprint VARCHAR(128) NOT NULL,
                      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                      UNIQUE(note_id, fingerprint)
                    )
                """))
                # En algunos despliegues antiguos la tabla pudo existir sin la
                # restricción única requerida por ON CONFLICT. Creamos un índice
                # único compatible para que Postgres acepte el ON CONFLICT.
                try:
                    cx.execute(sa.text(
                        "CREATE UNIQUE INDEX IF NOT EXISTS like_log_note_id_fingerprint_key ON like_log(note_id, fingerprint)"
                    ))
                except Exception:
                    pass
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
        except Exception as exc:
            msg = str(exc).lower()
            if "database is locked" in msg or "deadlock" in msg or "timeout" in msg:
                return jsonify(ok=False, error="db_busy"), 503
            return jsonify(ok=False, error="server_error"), 500

    @app.post("/api/notes/<int:note_id>/view")
    def view_note(note_id: int):
        fp = _get_fp(request)
        today = date.today().isoformat()
        now = _now()
        try:
            with _engine().begin() as cx:
                cx.execute(sa.text("""
                    CREATE TABLE IF NOT EXISTS view_log(
                      note_id INTEGER NOT NULL,
                      fingerprint VARCHAR(128) NOT NULL,
                      day TEXT NOT NULL,
                      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                      UNIQUE(note_id, fingerprint, day)
                    )
                """))
                # Asegurar índice único para ON CONFLICT (despliegues legados)
                try:
                    cx.execute(sa.text(
                        "CREATE UNIQUE INDEX IF NOT EXISTS view_log_note_id_fingerprint_day_key ON view_log(note_id, fingerprint, day)"
                    ))
                except Exception:
                    pass
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
        except Exception as exc:
            msg = str(exc).lower()
            if "database is locked" in msg or "deadlock" in msg or "timeout" in msg:
                return jsonify(ok=False, error="db_busy"), 503
            return jsonify(ok=False, error="server_error"), 500

    @app.post("/api/notes/<int:note_id>/report")
    def report_note(note_id: int):
        fp = _get_fp(request)
        reason = (request.json or {}).get("reason") if request.is_json else (request.form.get("reason") if request.form else None)
        now = _now()
        try:
            with _engine().begin() as cx:
                cx.execute(sa.text("""
                    CREATE TABLE IF NOT EXISTS report_log(
                      note_id INTEGER NOT NULL,
                      fingerprint VARCHAR(128) NOT NULL,
                      reason TEXT,
                      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                      UNIQUE(note_id, fingerprint)
                    )
                """))
                # Asegurar índice único para ON CONFLICT (despliegues legados)
                try:
                    cx.execute(sa.text(
                        "CREATE UNIQUE INDEX IF NOT EXISTS report_log_note_id_fingerprint_key ON report_log(note_id, fingerprint)"
                    ))
                except Exception:
                    pass
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
        except Exception as exc:
            msg = str(exc).lower()
            if "database is locked" in msg or "deadlock" in msg or "timeout" in msg:
                return jsonify(ok=False, error="db_busy"), 503
            return jsonify(ok=False, error="server_error"), 500

def register_alias_into(app):
    # Hoy no hay alias extra; dejamos el nombre expuesto porque el wsgi-bridge lo llama.
    return register_into(app)
