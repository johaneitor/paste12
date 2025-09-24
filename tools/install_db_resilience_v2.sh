#!/usr/bin/env bash
set -euo pipefail

mkdir -p backend

cat > backend/db_resilience.py <<'PY'
from sqlalchemy import text
from sqlalchemy.exc import OperationalError
from flask import jsonify

def attach(app, db):
    @app.before_request
    def _pre_ping():
        try:
            db.session.execute(text("SELECT 1"))
        except OperationalError:
            # reciclamos conexiones rotas (SSL EOF / bad mac)
            try:
                db.session.remove()
                db.engine.dispose()
            except Exception:
                pass

    @app.errorhandler(OperationalError)
    def _db_error(e):
        try:
            db.session.remove()
            db.engine.dispose()
        finally:
            return jsonify({"ok": False, "error": "db_unavailable"}), 503
PY

# Pega el attach en contract_shim sin acoplar fuerte
python - <<'PY'
import io, re
p="contract_shim.py"
s=io.open(p,"r",encoding="utf-8").read()
orig=s
if "db_resilience.attach(" not in s:
    inj = """
# --- db resilience glue ---
try:
    from backend import __init__ as backend_init  # para 'db' si existe
    from backend.db_resilience import attach as _db_attach
    if hasattr(application, "before_request"):  # Flask app
        _db = getattr(backend_init, "db", None) or application.extensions.get("sqlalchemy").db if hasattr(application, "extensions") and application.extensions.get("sqlalchemy") else None
        if _db is not None:
            _db_attach(application, _db)
except Exception as _e:
    # no frena el arranque; visible sólo en logs
    pass
# --- end db resilience glue ---
"""
    s = re.sub(r'(application\s*=\s*FrontendOverlay\(.*?\)\n)', r'\1'+inj, s, flags=re.S, count=1)
if s!=orig:
    io.open(p,"w",encoding="utf-8").write(s)
    print("[db-resilience] pegado en contract_shim.py")
else:
    print("[db-resilience] ya presente")
PY

python -m py_compile backend/db_resilience.py contract_shim.py || { echo "py_compile FAIL"; exit 3; }
echo "OK: DB resilience instalado."
