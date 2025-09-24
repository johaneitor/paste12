#!/usr/bin/env bash
set -euo pipefail
TS="$(date -u +%Y%m%d-%H%M%SZ)"
[[ -f backend/__init__.py ]] && cp -f backend/__init__.py backend/__init__.py.$TS.bak || true

# 1) módulo aislado
cat > backend/pooling_guard.py <<'PY'
from sqlalchemy import event
from sqlalchemy.exc import OperationalError, DisconnectionError

def attach_pooling(app, db):
    # engine options por config (Flask-SQLAlchemy los respeta)
    app.config.setdefault("SQLALCHEMY_ENGINE_OPTIONS", {
        "pool_pre_ping": True,
        "pool_recycle": 280,
        "pool_size": 5,
        "max_overflow": 5,
    })
    eng = db.engine

    @event.listens_for(eng, "engine_connect")
    def ping_connection(conn, branch):
        if branch:
            return
        try:
            conn.scalar("SELECT 1")
        except Exception:
            raise DisconnectionError()

    @event.listens_for(eng, "checkout")
    def checkout(dbapi_conn, conn_rec, conn_proxy):
        # lugar para checks extras si hiciera falta
        return
PY

# 2) import + hook en create_app (idempotente)
python - <<'PY'
import io, re
p="backend/__init__.py"
s=io.open(p,"r",encoding="utf-8").read(); orig=s
if "from .pooling_guard import attach_pooling" not in s:
    s=s.replace("from . import db","from . import db\nfrom .pooling_guard import attach_pooling")
if re.search(r'attach_pooling\(\s*app\s*,\s*db\s*\)', s) is None:
    s=re.sub(r'(def\s+create_app\(.*?\):\s*\n\s*app\s*=.*?\n)',
             r'\1    attach_pooling(app, db)\n',
             s, flags=re.S)
if s!=orig:
    io.open(p,"w",encoding="utf-8").write(s); print("[init] pooling_guard enganchado")
else:
    print("[init] pooling_guard ya estaba")
PY

python -m py_compile backend/__init__.py backend/pooling_guard.py && echo "py_compile OK"
