#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
cd "$(dirname "$0")"
ts=$(date +%s)

# Backup
cp -p backend/__init__.py "backend/__init__.py.bak.$ts" 2>/dev/null || true

# Reescritura limpia de backend/__init__.py
cat > backend/__init__.py <<'PYCODE'
# backend/__init__.py — clean reset: DB + Limiter + API + static frontend
import os
from datetime import timezone
from flask import Flask, send_from_directory, abort
from flask_sqlalchemy import SQLAlchemy
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from sqlalchemy import text

# Extensiones como singletons a nivel módulo (para 'from backend import db, limiter')
db = SQLAlchemy()
limiter = Limiter(key_func=get_remote_address, default_limits=[])

def _abs(path: str) -> str:
    return os.path.abspath(os.path.join(os.path.dirname(__file__), path))

def _build_database_uri() -> str:
    url = os.getenv("DATABASE_URL")
    if not url:
        os.makedirs(_abs("../instance"), exist_ok=True)
        return "sqlite:///" + _abs("../instance/production.db")
    if url.startswith(("postgres://", "postgresql://")) and "sslmode=" not in url:
        url += ("&" if "?" in url else "?") + "sslmode=require"
    return url

def create_app():
    static_folder = _abs("../frontend")
    app = Flask(__name__, static_folder=static_folder, static_url_path="")

    # ---- Config DB (con keepalive para Render) ----
    app.config["SQLALCHEMY_DATABASE_URI"] = _build_database_uri()
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {
        "pool_pre_ping": True,
        "pool_recycle": 280,
    }

    # Inicializar extensiones
    db.init_app(app)
    limiter.init_app(app)

    # Migración mínima (SQLAlchemy 2.x-safe)
    with app.app_context():
        try:
            from . import models  # asegura que los modelos se registren
            db.create_all()
            with db.engine.begin() as conn:
                conn.execute(text("SELECT 1"))
        except Exception as e:
            app.logger.warning(f"migrate_min: {e}")

    # Registrar API
    try:
        from .routes import bp as api_bp
        app.register_blueprint(api_bp, url_prefix="/api")
    except Exception as e:
        app.logger.error(f"No se pudo registrar blueprint API: {e}")

    # Rutas de frontend (idempotentes, sin decoradores)
    def _register_frontend(app):
        sf = app.static_folder

        # /favicon.ico
        if "/favicon.ico" not in {r.rule for r in app.url_map.iter_rules()}:
            app.add_url_rule(
                "/favicon.ico",
                endpoint="static_favicon",
                view_func=lambda: send_from_directory(sf, "favicon.svg", mimetype="image/svg+xml"),
            )

        # /ads.txt
        if "/ads.txt" not in {r.rule for r in app.url_map.iter_rules()}:
            app.add_url_rule(
                "/ads.txt",
                endpoint="static_ads",
                view_func=lambda: send_from_directory(sf, "ads.txt", mimetype="text/plain"),
            )

        # /
        if "/" not in {r.rule for r in app.url_map.iter_rules()}:
            app.add_url_rule(
                "/",
                endpoint="static_root",
                view_func=lambda: send_from_directory(sf, "index.html"),
            )

        # Fallback SPA y archivos estáticos
        if "static_any" not in app.view_functions:
            def static_any(path):
                if path.startswith("api/"):
                    return abort(404)
                full = os.path.join(sf, path)
                if os.path.isfile(full):
                    return send_from_directory(sf, path)
                return send_from_directory(sf, "index.html")
            app.add_url_rule("/<path:path>", endpoint="static_any", view_func=static_any)

    _register_frontend(app)
    return app
PYCODE

# Pruebas locales rápidas
python -m py_compile backend/__init__.py

python - <<'PY'
import os, sys
sys.path.insert(0, os.getcwd())
from backend import create_app
a = create_app()
rules = {r.rule for r in a.url_map.iter_rules()}
print("✓ static:", a.static_folder)
print("✓ básicos:", sorted(rules & {"/","/favicon.ico","/ads.txt"}))
print("✓ api?:", any(str(r.rule).startswith("/api/") for r in a.url_map.iter_rules()))
PY

# Commit + push → redeploy en Render
git add backend/__init__.py
git commit -m "chore(init): clean rewrite (__init__ con DB, limiter, API y rutas estáticas) — corrige IndentationError" || true
git push -u origin "$(git rev-parse --abbrev-ref HEAD)"

echo "🚀 Listo. Cuando Render termine, abre: https://paste12-rmsk.onrender.com/?v=$ts y verifica /api/notes"
