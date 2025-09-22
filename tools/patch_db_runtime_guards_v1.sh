#!/usr/bin/env bash
set -euo pipefail

# 1) Crear módulo db_runtime_guards.py (idempotente)
cat > db_runtime_guards.py <<'PY'
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
PY

# 2) Inyectar llamada en wsgi.py (idempotente)
WSGI="wsgi.py"
[[ -f "$WSGI" ]] || { echo "ERR: no existe $WSGI"; exit 1; }

python - "$WSGI" <<'PY'
import io,sys,re,os
p = sys.argv[1]
s = open(p,'r',encoding='utf-8',errors='ignore').read()
if "db_runtime_guards" in s and "db_runtime_guards.install(" in s:
    print("→ wsgi.py ya tenía db_runtime_guards.install()")
    sys.exit(0)

# Buscamos la importación de la aplicación WSGI para colgarnos debajo
pat = re.compile(r'^(from\s+contract_shim\s+import\s+application[^\n]*\n)', re.M)
m = pat.search(s)
hook = (
    "try:\n"
    "    import db_runtime_guards as _dbg\n"
    "    _dbg.install(application)\n"
    "except Exception as _e:\n"
    "    try:\n"
    "        import sys; print('db guards skipped:', _e, file=sys.stderr)\n"
    "    except Exception:\n"
    "        pass\n"
)
if m:
    s = s[:m.end()] + hook + s[m.end():]
else:
    # fallback: al principio del archivo
    s = hook + s

open(p,'w',encoding='utf-8').write(s)
print("✓ wsgi.py parchado con db_runtime_guards.install()")
PY

# 3) Sanity de sintaxis
python - <<'PY'
import py_compile
py_compile.compile('db_runtime_guards.py', doraise=True)
py_compile.compile('wsgi.py', doraise=True)
print("✓ py_compile OK")
PY

echo "Listo. Aplica commit/push y redeploy."
