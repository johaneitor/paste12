#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
cd "$(dirname "$0")"
ts=$(date +%s)

# Backups
cp -p backend/__init__.py "backend/__init__.py.bak.$ts" 2>/dev/null || true
mkdir -p frontend
[ -f frontend/ads.txt ] || echo "google.com, pub-9479870293204581, DIRECT, f08c47fec0942fa0" > frontend/ads.txt
if ! [ -f frontend/favicon.svg ]; then
  cat > frontend/favicon.svg <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <defs><linearGradient id="g" x1="0" x2="0" y1="0" y2="1">
    <stop offset="0" stop-color="#00c2c7"/><stop offset="1" stop-color="#37ffd9"/>
  </linearGradient></defs>
  <rect width="64" height="64" rx="12" ry="12" fill="#0d1b2a"/>
  <g fill="url(#g)" stroke="#37ffd9" stroke-width="2">
    <path d="M18 10h28v8c0 6-9 12-14 14c5 2 14 8 14 14v8H18v-8c0-6 9-12 14-14c-5-2-14-8-14-14z"/>
  </g>
</svg>
SVG
fi

# Reescribir backend/__init__.py con una versión estable y limpia
cat > backend/__init__.py <<'PY'
import os
from datetime import datetime, timezone
from flask import Flask, send_from_directory
from flask_sqlalchemy import SQLAlchemy
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from flask_cors import CORS
from sqlalchemy import text

try:
    from flask_compress import Compress
except Exception:  # lib opcional
    Compress = None

# Extensiones exportadas para: from . import db, limiter
db = SQLAlchemy()
limiter = Limiter(key_func=get_remote_address, default_limits=[])

def _database_uri() -> str:
    uri = os.getenv("DATABASE_URL") or os.getenv("SQLALCHEMY_DATABASE_URI")
    if not uri:
        os.makedirs("instance", exist_ok=True)
        return "sqlite:///instance/production.db"
    # Render a veces da postgres:// (depre)
    return uri.replace("postgres://", "postgresql+psycopg2://")

def create_app():
    app = Flask(__name__, static_folder="frontend", static_url_path="")
    app.config.update(
        SQLALCHEMY_DATABASE_URI=_database_uri(),
        SQLALCHEMY_TRACK_MODIFICATIONS=False,
    )

    # Pooling/SSL recomendado para Postgres en Render
    if app.config["SQLALCHEMY_DATABASE_URI"].startswith("postgresql"):
        app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {
            "pool_pre_ping": True,
            "pool_recycle": 300,
            "pool_size": 5,
            "max_overflow": 10,
        }
    else:  # SQLite local
        app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {
            "connect_args": {"check_same_thread": False}
        }

    CORS(app)
    if Compress:
        Compress(app)

    db.init_app(app)
    limiter.init_app(app)

    # Migración mínima compatible con SQLAlchemy 2.x
    with app.app_context():
        db.create_all()
        try:
            with db.engine.begin() as conn:
                conn.execute(text("SELECT 1"))
        except Exception as e:
            app.logger.warning(f"migrate_min: {e}")

    # ---- Rutas estáticas básicas (deben ir DESPUÉS de crear app) ----
    @app.get("/favicon.ico")
    def _favicon():
        return send_from_directory(app.static_folder, "favicon.svg", mimetype="image/svg+xml")

    @app.get("/ads.txt")
    def _ads_txt():
        return send_from_directory(app.static_folder, "ads.txt", mimetype="text/plain")

    @app.route("/")
    def index():
        return send_from_directory(app.static_folder, "index.html")

    @app.get("/healthz")
    def _healthz():
        return {"ok": True, "ts": datetime.now(timezone.utc).isoformat()}

    # API
    from . import routes  # noqa: WPS433
    app.register_blueprint(routes.bp)

    return app
PY

# Validar sintaxis
python -m py_compile backend/__init__.py

# Commit + push (forzar redeploy en Render)
git add backend/__init__.py frontend/ads.txt frontend/favicon.svg
git commit -m "fix(init): reordenar rutas estáticas tras app=Flask; init DB/Limiter estable; migrate_min SA2.x" || true
git push -u origin "$(git rev-parse --abbrev-ref HEAD)"

echo "🚀 Subido. Cuando Render termine, prueba:
/?v=$ts  (cache-bust)
/favicon.ico y /ads.txt"
