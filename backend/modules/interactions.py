from __future__ import annotations
from datetime import datetime, timezone, date
import hashlib
import os
import random
import sqlite3
import time
from typing import Optional, Callable, Any

_ENGINE_SINGLETON: Optional["Engine"] = None

def _engine():
    """Create (once) a dedicated SQLAlchemy Engine (fallback only).
    Prefer using Flask's db.engine when available to avoid extra pools.
    """
    global _ENGINE_SINGLETON
    if _ENGINE_SINGLETON is not None:
        return _ENGINE_SINGLETON

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
            # Keep this pool small to avoid exhausting server connections
            opts.update({"pool_size": 3, "max_overflow": 5, "pool_recycle": 280})
        elif url.startswith("sqlite"):
            # Reduce lock errors under light concurrency
            opts.update({"connect_args": {"timeout": 5.0}})
    except Exception:
        pass

    eng = create_engine(url, **opts)

    # Ensure SQLite pragmas on this engine (idempotent; safe no-op for others)
    from sqlalchemy.engine import Engine as _Eng
    @event.listens_for(_Eng, "connect")
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

    _ENGINE_SINGLETON = eng
    return eng

def _get_engine():
    """Return the primary Engine (Flask db.engine) or fallback singleton."""
    try:
        # Import here to avoid circular imports at module load time
        from backend import db  # type: ignore
        eng = getattr(db, "engine", None)
        if eng is not None:
            return eng
    except Exception:
        pass
    return _engine()

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

def _is_transient_db_error(exc: Exception) -> bool:
    """Classify errors that are safe to retry (deadlocks, serialization, busy/locked).

    Works across SQLite and Postgres by matching on common substrings.
    """
    msg = (str(getattr(exc, "orig", exc)) or "").lower()
    return (
        "deadlock" in msg
        or "could not serialize" in msg
        or "serialization failure" in msg
        or "database is locked" in msg
        or "lock timeout" in msg
        or "timeout" in msg and "statement" in msg
    )

def _retry_on_transient_errors(func: Callable[[], Any], *, attempts: int = 5, base_delay: float = 0.05) -> Any:
    """Execute callable with exponential backoff on transient DB errors.

    - Retries up to `attempts` times
    - Backoff: base_delay * 2^(n-1) + jitter
    """
    last_exc: Optional[Exception] = None
    for i in range(1, max(1, attempts) + 1):
        try:
            return func()
        except Exception as exc:  # broad by design; we classify below
            last_exc = exc
            if not _is_transient_db_error(exc) or i >= attempts:
                break
            # Exponential backoff with jitter (cap small to keep API responsive)
            sleep_s = min(1.0, base_delay * (2 ** (i - 1)) + random.uniform(0, base_delay))
            time.sleep(sleep_s)
            continue
    if last_exc is not None:
        raise last_exc
    # Should never reach here
    return None

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
            with _get_engine().begin() as cx:
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

    # Rate-limit: one view write per IP+note per minute (plus a coarse global cap)
    try:
        from backend import limiter  # late import to avoid circular import issues
        from flask import request as _rq

        def _rate_key_view():
            try:
                return f"{_rq.remote_addr}:{_rq.view_args.get('note_id')}"
            except Exception:
                return (_rq.remote_addr or "anon")
    except Exception:  # pragma: no cover - if limiter not available, continue without per-endpoint limits
        limiter = None  # type: ignore
        _rate_key_view = None  # type: ignore

    decorator = (limiter.limit("30 per minute", key_func=_rate_key_view) if limiter else (lambda f: f))

    @decorator
    def _view_note_impl(note_id: int):
        fp = _get_fp(request)
        today = date.today().isoformat()
        now = _now()
        try:
            def _tx_call():
                with _get_engine().begin() as cx:
                    # Minimal DDL safety; harmless if table already exists
                    cx.execute(sa.text(
                        """
                        CREATE TABLE IF NOT EXISTS view_log(
                          note_id INTEGER NOT NULL,
                          fingerprint VARCHAR(128) NOT NULL,
                          day TEXT NOT NULL,
                          created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                          UNIQUE(note_id, fingerprint, day)
                        )
                        """
                    ))
                    # Ensure unique index for Postgres ON CONFLICT acceptance (legacy deployments)
                    try:
                        cx.execute(sa.text(
                            "CREATE UNIQUE INDEX IF NOT EXISTS view_log_note_id_fingerprint_day_key ON view_log(note_id, fingerprint, day)"
                        ))
                    except Exception:
                        pass

                    # Idempotent attempt per (note_id, fp, day)
                    inserted = _insert_ignore(
                        cx,
                        "view_log",
                        ["note_id", "fingerprint", "day", "created_at"],
                        {"note_id": note_id, "fingerprint": fp, "day": today, "created_at": now},
                        conflict=["note_id", "fingerprint", "day"],
                    )
                    if inserted:
                        cx.execute(sa.text("UPDATE notes SET views = COALESCE(views,0) + 1 WHERE id=:id"), {"id": note_id})
                    row = cx.execute(sa.text("SELECT id, COALESCE(views,0) AS views FROM notes WHERE id=:id"), {"id": note_id}).first()
                    if not row:
                        # Surface as 404 outside the retry loop
                        raise LookupError("not_found")
                    return jsonify(ok=True, id=row.id, views=row.views), 200

            return _retry_on_transient_errors(_tx_call, attempts=5, base_delay=0.05)
        except LookupError:
            return jsonify(ok=False, error="not_found"), 404
        except Exception as exc:
            msg = str(getattr(exc, "orig", exc)).lower()
            if "database is locked" in msg or "deadlock" in msg or "timeout" in msg or "could not serialize" in msg:
                return jsonify(ok=False, error="db_busy"), 503
            return jsonify(ok=False, error="server_error"), 500

    # Register the actual route (decorate only at registration time)
    @app.post("/api/notes/<int:note_id>/view")
    def view_note(note_id: int):
        return _view_note_impl(note_id)

    @app.post("/api/notes/<int:note_id>/report")
    def report_note(note_id: int):
        fp = _get_fp(request)
        reason = (request.json or {}).get("reason") if request.is_json else (request.form.get("reason") if request.form else None)
        now = _now()
        try:
            with _get_engine().begin() as cx:
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
