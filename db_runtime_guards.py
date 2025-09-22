import os, sys
from typing import Optional

def install(app):
    # 0) Forzar ssl si falta
    try:
        os.environ.setdefault("PGSSLMODE", "require")
    except Exception:
        pass

    # 1) Localizar db (Flask-SQLAlchemy)
    db = None
    try:
        from backend.models import db as _db
        db = _db
    except Exception:
        try:
            from models import db as _db
            db = _db
        except Exception:
            db = None

    engine = None
    if db is not None:
        try:
            engine = getattr(db, "engine", None) or db.get_engine(app)
        except Exception as e:
            print("db guards: no engine yet:", e, file=sys.stderr)

    # 2) Instalar pre-ping por evento (simula pool_pre_ping si engine ya existe)
    if engine is not None:
        try:
            from sqlalchemy import event, text, exc
            @event.listens_for(engine, "engine_connect")
            def _ping(conn, branch):
                if branch:
                    return
                try:
                    conn.scalar(text("SELECT 1"))
                except exc.DBAPIError as err:
                    if getattr(err, "connection_invalidated", False):
                        conn.scalar(text("SELECT 1"))
                    else:
                        raise
            # intentar reciclar conexiones envejecidas
            try:
                engine.pool._recycle = int(os.getenv("SQLA_POOL_RECYCLE", "300"))
            except Exception:
                pass
            print("db guards: pre-ping on engine_connect active", file=sys.stderr)
        except Exception as e:
            print("db guards: pre-ping install skipped:", e, file=sys.stderr)

    # 3) Ping liviano antes de cada request (no interrumpe la request si falla)
    try:
        from sqlalchemy import text
        @app.before_request
        def _pre_ping():
            if db is None:
                return
            try:
                db.session.execute(text("SELECT 1"))
            except Exception:
                try:
                    db.session.rollback()
                    if engine is not None:
                        engine.dispose()
                except Exception:
                    pass
    except Exception as e:
        print("db guards: before_request ping skipped:", e, file=sys.stderr)

    # 4) Manejador global de errores operacionales -> 503 + rollback
    try:
        from sqlalchemy.exc import OperationalError
        @app.errorhandler(OperationalError)
        def _on_db_error(e):
            try:
                if db is not None:
                    db.session.rollback()
            except Exception:
                pass
            return app.response_class(
                response='{"ok":false,"error":"db_unavailable"}',
                status=503,
                mimetype="application/json"
            )
    except Exception as e:
        print("db guards: errorhandler skipped:", e, file=sys.stderr)
