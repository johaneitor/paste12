#!/usr/bin/env bash
set -Eeuo pipefail
ts=$(date +%s)

# 1) Backup
cp -p backend/__init__.py "backend/__init__.py.bak.$ts" 2>/dev/null || true

# 2) Reescribir backend/__init__.py con una versión limpia
cat > backend/__init__.py <<'PY'
# backend/__init__.py — versión mínima y estable
from __future__ import annotations

import os
from pathlib import Path
from flask import Flask, send_from_directory, abort
from flask_sqlalchemy import SQLAlchemy
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from sqlalchemy import text

# Extensiones como singletons (no recrear en cada import)
db = SQLAlchemy()
limiter = Limiter(key_func=get_remote_address, default_limits=[])

def _abs(rel: str) -> str:
    return str((Path(__file__).parent / rel).resolve())

def _database_uri() -> str:
    # Render usa DATABASE_URL; fallback a SQLALCHEMY_DATABASE_URI; sino: SQLite local
    uri = os.getenv("DATABASE_URL") or os.getenv("SQLALCHEMY_DATABASE_URI")
    if uri:
        return uri
    inst = (Path(__file__).parent / ".." / "instance").resolve()
    inst.mkdir(parents=True, exist_ok=True)
    return f"sqlite:///{inst / 'production.db'}"

def create_app() -> Flask:
    app = Flask(
        __name__,
        static_folder=_abs("../frontend"),
        static_url_path="",
    )

    # ---- Config DB (con keepalive) ----
    app.config["SQLALCHEMY_DATABASE_URI"] = _database_uri()
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {
        "pool_pre_ping": True,
        "pool_recycle": 280,
    }

    # ---- Inicializar extensiones (idempotente) ----
    try:
        db.init_app(app)
    except Exception:
        pass
    try:
        limiter.init_app(app)
    except Exception:
        pass

    # ---- Migración mínima + índices ----
    with app.app_context():
        try:
            from . import models  # registra modelos
            db.create_all()
            with db.engine.begin() as conn:
                conn.execute(text("CREATE INDEX IF NOT EXISTS ix_note_expires_at ON note (expires_at)"))
                conn.execute(text("CREATE INDEX IF NOT EXISTS ix_note_exp_ts   ON note (expires_at, timestamp)"))
                conn.execute(text("CREATE INDEX IF NOT EXISTS ix_note_ts_desc  ON note (timestamp DESC)"))
        except Exception as e:
            try:
                app.logger.warning(f"migrate_min: {e}")
            except Exception:
                print("migrate_min warn:", e)

    # ---- Registrar blueprint /api (idempotente) ----
    try:
        if "api" not in app.blueprints:
            from .routes import bp as api_bp
            app.register_blueprint(api_bp, url_prefix="/api")
    except Exception as e:
        try:
            app.logger.error(f"No se pudo registrar blueprint API: {e}")
        except Exception:
            print("API blueprint error:", e)

    # ---- Rutas estáticas/SPA (idempotentes; no capturar /api/*) ----
    try:
        rules = {r.rule for r in app.url_map.iter_rules()}

        if "/favicon.ico" not in rules:
            app.add_url_rule(
                "/favicon.ico",
                endpoint="static_favicon",
                view_func=lambda: send_from_directory(app.static_folder, "favicon.svg", mimetype="image/svg+xml"),
            )
        if "/ads.txt" not in rules:
            app.add_url_rule(
                "/ads.txt",
                endpoint="static_ads",
                view_func=lambda: send_from_directory(app.static_folder, "ads.txt", mimetype="text/plain"),
            )
        if "/" not in rules:
            app.add_url_rule(
                "/",
                endpoint="static_root",
                view_func=lambda: send_from_directory(app.static_folder, "index.html"),
            )
        if "static_any" not in app.view_functions:
            def static_any(path: str):
                if path.startswith("api/"):
                    return abort(404)
                full = os.path.join(app.static_folder, path)
                if os.path.isfile(full):
                    return send_from_directory(app.static_folder, path)
                return send_from_directory(app.static_folder, "index.html")
            app.add_url_rule("/<path:path>", endpoint="static_any", view_func=static_any)
    except Exception as e:
        try:
            app.logger.warning(f"Rutas estáticas: {e}")
        except Exception:
            print("static routes warn:", e)

    return app
PY

# 3) Validación de sintaxis
python -m py_compile backend/__init__.py

# 4) Smoke rápido de rutas
python - <<'PY'
import os, sys
sys.path.insert(0, os.getcwd())
from backend import create_app
a = create_app()
rules = sorted([(r.rule, ",".join(sorted(r.methods-{"HEAD","OPTIONS"})), r.endpoint) for r in a.url_map.iter_rules()], key=lambda x:x[0])
print("🛣️  Rutas registradas:")
for r in rules:
    print(" - {:<28} | {:<10} | {}".format(*r))
print("¿/api/notes presente?:", any(rr[0]=="/api/notes" and "GET" in rr[1] for rr in rules))
PY

echo
echo "✅ __init__.py reseteado. Ahora sube y redeploy:"
echo "  git add backend/__init__.py && git commit -m 'fix(init): versión mínima estable de create_app' || true"
echo "  git push -u origin main"
echo "Luego prueba:"
echo "  curl -sSf https://paste12-rmsk.onrender.com/api/health || true"
echo "  curl -sSf 'https://paste12-rmsk.onrender.com/api/notes?page=1' | head -c 400; echo"
