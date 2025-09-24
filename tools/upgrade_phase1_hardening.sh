#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(pwd)"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
LOG="$PREFIX/tmp/paste12_server.log"
mkdir -p "$PREFIX/tmp" data tools

backup(){ [ -f "$1" ] && cp -f "$1" "$1.bak.$(date +%s)" || true; }

echo "➤ Backups"
backup backend/__init__.py
backup backend/routes.py
backup frontend/js/app.js
backup requirements.txt

echo "➤ Reescribiendo backend/__init__.py con Limiter (opcional) y limpieza programable"
cat > backend/__init__.py <<'PY'
from __future__ import annotations
import os, re, logging, threading, time, json
from datetime import datetime, timedelta, date
from flask import Flask, g, request
from flask_sqlalchemy import SQLAlchemy

# Extensiones
db = SQLAlchemy()

# Limiter opcional (no revienta si no está instalado)
try:
    from flask_limiter import Limiter
    from flask_limiter.util import get_remote_address
    class _LimiterWrapper:
        def __init__(self): self._limiter = None
        def init_app(self, app):
            def key_func():
                uid = request.cookies.get('uid')
                return uid or get_remote_address()
            self._limiter = Limiter(key_func=key_func, default_limits=[])
            self._limiter.init_app(app)
        def limit(self, *a, **k):
            if self._limiter is None:
                def deco(f): return f
                return deco
            return self._limiter.limit(*a, **k)
    limiter = _LimiterWrapper()
except Exception:
    class _NoopLimiter:
        def init_app(self, app): pass
        def limit(self, *a, **k):
            def deco(f): return f
            return deco
    limiter = _NoopLimiter()

def _db_uri() -> str:
    uri = os.getenv("DATABASE_URL")
    if uri:
        uri = re.sub(r"^postgres://", "postgresql+psycopg://", uri)
        if uri.startswith("postgresql://") and "+psycopg://" not in uri:
            uri = uri.replace("postgresql://","postgresql+psycopg://",1)
        return uri
    import pathlib
    return f"sqlite:///{pathlib.Path('data/app.db').resolve()}"

def _cleanup_once(app: Flask):
    """Borra expiradas y logs viejos (seguro para SQLite/Postgres)."""
    from .models import Note, LikeLog, ViewLog, ReportLog  # import diferido
    with app.app_context():
        now = datetime.utcnow()
        try:
            db.session.query(Note).filter(
                Note.expires_at.isnot(None),
                Note.expires_at < now
            ).delete(synchronize_session=False)
        except Exception as e:
            app.logger.warning(f"cleanup notes: {e}")
        try:
            db.session.query(ViewLog).filter(
                ViewLog.view_date < (now.date() - timedelta(days=30))
            ).delete(synchronize_session=False)
            db.session.query(LikeLog).filter(
                LikeLog.created_at < (now - timedelta(days=90))
            ).delete(synchronize_session=False)
            db.session.query(ReportLog).filter(
                ReportLog.created_at < (now - timedelta(days=180))
            ).delete(synchronize_session=False)
        except Exception as e:
            app.logger.warning(f"cleanup logs: {e}")
        db.session.commit()

def _maybe_schedule_cleanup(app: Flask):
    if os.getenv("ENABLE_CLEANUP_LOOP","0") != "1":
        return
    interval = int(os.getenv("CLEANUP_EVERY_SECONDS","21600"))  # 6h
    def loop():
        while True:
            try: _cleanup_once(app)
            except Exception as e: app.logger.warning(f"cleanup loop: {e}")
            time.sleep(interval)
    t = threading.Thread(target=loop, daemon=True)
    t.start()

def create_app() -> Flask:
    app = Flask(__name__)
    app.config["SQLALCHEMY_DATABASE_URI"] = _db_uri()
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {"pool_pre_ping": True, "pool_recycle": 280}

    db.init_app(app)
    try: limiter.init_app(app)
    except Exception as e: app.logger.warning(f"Limiter init: {e}")

    # logging simple (JSON) si LOG_JSON=1
    if os.getenv("LOG_JSON","0") == "1":
        @app.before_request
        def _t0(): g._t0 = time.perf_counter()
        @app.after_request
        def _log(resp):
            try:
                dt = int((time.perf_counter() - getattr(g,"_t0",time.perf_counter()))*1000)
                app.logger.info(json.dumps({"m":request.method,"p":request.path,"s":resp.status_code,"ms":dt}))
            except Exception: pass
            return resp

    from .routes import api as api_blueprint
    app.register_blueprint(api_blueprint)

    with app.app_context():
        db.create_all()

    _maybe_schedule_cleanup(app)
    return app
PY

echo "➤ Parcheando backend/routes.py (fingerprint con cookie UID + rate limits + endpoint admin/cleanup)"
python - <<'PY'
from pathlib import Path
import re, os
p = Path("backend/routes.py")
s = p.read_text(encoding="utf-8")

if "from backend import db" not in s:
    s = s.replace("from backend.models import Note", "from backend import db\nfrom backend.models import Note")

# importar limiter y os
if "from backend import limiter" not in s:
    s = s.replace("from backend import db", "from backend import db, limiter")
if "import os" not in s:
    s = s.replace("from hashlib import sha256", "from hashlib import sha256\nimport os")

# fingerprint: usar cookie 'uid' si existe
s = re.sub(
    r"def _fingerprint_from_request\(req\):[\s\S]*?return sha256\([^\n]+",
    """def _fingerprint_from_request(req):
    uid = req.cookies.get('uid')
    if uid and len(uid) >= 8:
        base = f"uid:{uid}"
    else:
        ip = (req.headers.get("X-Forwarded-For") or getattr(req, "remote_addr", "") or "").split(",")[0].strip()
        ua = req.headers.get("User-Agent", "")
        base = f"{ip}|{ua}"
    return sha256(base.encode("utf-8")).hexdigest()""",
    s, flags=re.S
)

# añadir /api/admin/cleanup (token en ADMIN_TOKEN)
if "/admin/cleanup" not in s:
    s += """

@api.route("/admin/cleanup", methods=["POST","GET"])
def admin_cleanup():
    token = os.getenv("ADMIN_TOKEN","")
    provided = (request.args.get("token") or request.headers.get("X-Admin-Token") or "")
    if not token or provided != token:
        return jsonify({"error":"forbidden"}), 403
    try:
        from flask import current_app
        from backend.__init__ import _cleanup_once
        _cleanup_once(current_app)
        return jsonify({"ok": True}), 200
    except Exception as e:
        return jsonify({"error": "cleanup_failed", "detail": str(e)}), 500
"""

# añadir decoradores limiter.limit a endpoints clave
s = re.sub(r'(@api\.route\("/notes", methods=\["POST"\]\)\s*\ndef\s+create_note)', r'@limiter.limit("5/minute")\n\1', s)
s = re.sub(r'(@api\.route\("/notes/<int:note_id>/like", methods=\["POST"\]\)\s*\ndef\s+like_note)', r'@limiter.limit("30/minute")\n\1', s)
s = re.sub(r'(@api\.route\("/notes/<int:note_id>/view", methods=\["POST"\]\)\s*\ndef\s+view_note)', r'@limiter.limit("30/minute")\n\1', s)
s = re.sub(r'(@api\.route\("/notes/<int:note_id>/report", methods=\["POST"\]\)\s*\ndef\s+report_note)', r'@limiter.limit("30/minute")\n\1', s)

p.write_text(s, encoding="utf-8")
print("routes.py actualizado.")
PY

echo "➤ Asegurar cookie UID en frontend/js/app.js"
python - <<'PY'
from pathlib import Path
p = Path("frontend/js/app.js")
s = p.read_text(encoding="utf-8") if p.exists() else "(function(){})();"
if "ensureUid" not in s:
    s = s.replace("(function(){", """(function(){
  // UID para unicidad de like/view
  (function ensureUid(){
    try{
      if(document.cookie.includes('uid=')) return;
      const rnd = (crypto && crypto.getRandomValues) ? Array.from(crypto.getRandomValues(new Uint8Array(16))).map(b=>b.toString(16).padStart(2,'0')).join('') : String(Math.random()).slice(2);
      document.cookie = "uid="+rnd+"; Max-Age="+(3600*24*365)+"; Path=/; SameSite=Lax";
    }catch(_){}
  })();""", 1)
p.write_text(s, encoding="utf-8")
print("app.js: ensureUid() inyectado.")
PY

echo "➤ requirements.txt (añadir Flask-Limiter si falta)"
if ! grep -qi '^Flask-Limiter' requirements.txt 2>/dev/null; then
  echo "Flask-Limiter==3.6.0" >> requirements.txt
fi

echo "➤ Reinicio y smokes"
pkill -f "python .*run\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "gunicorn" 2>/dev/null || true
sleep 1
# soporta tanto run.py como backend:create_app
if [ -f "run.py" ]; then
  nohup python run.py >"$LOG" 2>&1 & disown || true
else
  python - <<'PY' >/dev/null 2>&1 || true
from backend import create_app
app = create_app()
PY
fi
sleep 2
echo "health=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/api/health)"
echo "create=$(curl -sS -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -d '{\"text\":\"fase1\",\"hours\":24}' http://127.0.0.1:8000/api/notes)"
echo "notes=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/api/notes)"

echo "➤ Commit & push"
git add backend/__init__.py backend/routes.py frontend/js/app.js requirements.txt || true
git commit -m "feat(hardening): UID cookie + fingerprint; rate limits; cleanup endpoint/loop opcional" || true
git push origin main || true

echo "✓ Fase 1 lista. (Para loop: export ENABLE_CLEANUP_LOOP=1)"
