#!/usr/bin/env bash
set -Eeuo pipefail

WSGI="wsgi.py"
cp -a "$WSGI" "$WSGI.bak.$(date +%s)" 2>/dev/null || true

python - "$WSGI" <<'PY'
import io, sys
p = sys.argv[1]
s = io.open(p, 'r', encoding='utf-8').read()

marker = "# --- DB bind (init_app + create_all) ---"
if marker in s:
    print("db-bind: ya presente"); sys.exit(0)

block = f"""
{marker}
# Enlazar SQLAlchemy 'db' a la app actual (idempotente) y crear tablas si hace falta
_db = None
try:
    from backend import db as _db  # camino preferido
except Exception:
    try:
        from backend.db import db as _db  # fallback
    except Exception:
        _db = None

if _db is not None:
    try:
        _db.init_app(app)
        with app.app_context():
            try:
                import backend.models  # asegura que los modelos estén importados
            except Exception:
                pass
            try:
                _db.create_all()
            except Exception as _e:
                print("[wsgi] create_all skipped:", _e)
    except Exception as _e:
        print("[wsgi] db.init_app failed:", _e)
"""

s = s.rstrip() + "\n\n" + block + "\n"
io.open(p, 'w', encoding='utf-8').write(s)
print("db-bind: parcheado")
PY

git add wsgi.py || true
git commit -m "wsgi: bind SQLAlchemy (init_app+create_all) a la app actual" || true
git push origin main || true
