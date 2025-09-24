#!/usr/bin/env bash
set -Eeuo pipefail
ROUTES="backend/routes.py"

cp -a "$ROUTES" "$ROUTES.bak.$(date +%s)" 2>/dev/null || true

python - <<'PY'
from pathlib import Path
p = Path("backend/routes.py")
s = p.read_text(encoding="utf-8")
block = """
from flask import current_app, jsonify
import sqlalchemy as sa

@api.route("/api/dbdiag", methods=["GET"])  # type: ignore
def dbdiag():
    out = {}
    try:
        from backend import db  # type: ignore
        out["has_db"] = True
        # ¿la session tiene bind?
        try:
            bind = db.session.get_bind()
            out["session_bind"] = bool(bind)
            out["engine_str"] = str(bind.url) if bind else None
        except Exception as e:
            out["session_bind"] = False
            out["session_bind_err"] = str(e)

        # ¿puedo ejecutar SELECT 1?
        try:
            with current_app.app_context():
                conn = db.engine.connect()
                conn.execute(sa.text("SELECT 1"))
                conn.close()
            out["engine_ok"] = True
        except Exception as e:
            out["engine_ok"] = False
            out["engine_err"] = str(e)
    except Exception as e:
        out["has_db"] = False
        out["err"] = str(e)
    return jsonify(out), 200
"""
if "/api/dbdiag" not in s:
    s = s.rstrip() + "\n" + block
    p.write_text(s, encoding="utf-8")
    print("routes: agregado /api/dbdiag")
else:
    print("routes: ya tenía /api/dbdiag (ok)")
PY

git add backend/routes.py || true
git commit -m "diag(db): agregar /api/dbdiag para verificar bind y engine" || true
git push origin main || true

echo 'Listo. Probá:'
echo '  curl -sS https://paste12-rmsk.onrender.com/api/dbdiag | python -m json.tool'
