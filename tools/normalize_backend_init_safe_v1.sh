#!/usr/bin/env bash
set -euo pipefail

TARGET="backend/__init__.py"
[[ -f "$TARGET" ]] || { echo "ERROR: falta $TARGET"; exit 3; }

TS="$(date -u +%Y%m%d-%H%M%SZ)"
BAK="backend/__init__.py.$TS.bak"
cp -f "$TARGET" "$BAK"
echo "[init-fix] Backup: $BAK"

# Si compila, no tocamos nada
if python -m py_compile "$TARGET" 2>/dev/null; then
  echo "[init-fix] __init__.py compila. No hago cambios."
  exit 0
fi

# Reemplazo por una app factory segura conservando lo esencial.
cat > "$TARGET" <<'PYAPP'
from __future__ import annotations
import os
from flask import Flask, jsonify
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()

def _normalize_db_url(url: str) -> str:
    if not url:
        return url
    # postgres -> postgresql
    if url.startswith("postgres://"):
        url = "postgresql://" + url[len("postgres://"):]
    return url

def create_app() -> Flask:
    app = Flask(__name__, static_folder=None)
    CORS(app)

    db_url = _normalize_db_url(os.getenv("DATABASE_URL", ""))
    if not db_url:
        # Deja que SQLAlchemy use config por defecto si no hay URL
        app.config["SQLALCHEMY_DATABASE_URI"] = "sqlite://"
    else:
        app.config["SQLALCHEMY_DATABASE_URI"] = db_url

    # Pooling seguro
    app.config.setdefault("SQLALCHEMY_ENGINE_OPTIONS", {
        "pool_pre_ping": True,
        "pool_recycle": 280,
        "pool_timeout": 20,
        "pool_size": 5,
        "max_overflow": 5,
    })
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

    db.init_app(app)

    @app.get("/api/health")
    def health():
        return jsonify({"ok": True, "api": True, "ver": "init-safe-v1"})

    # Intentar registrar rutas existentes sin romper si no están
    try:
        # 1) attach_routes(app) si existe
        from . import routes as _routes
        if hasattr(_routes, "attach_routes"):
            _routes.attach_routes(app)  # type: ignore
        # 2) o blueprint 'bp'
        if hasattr(_routes, "bp"):
            app.register_blueprint(getattr(_routes, "bp"))
    except Exception as e:
        # seguimos; el health debe responder igual
        app.logger.warning("No pude registrar rutas: %r", e)

    return app

# WSGI app para gunicorn
app = create_app()
PYAPP

python -m py_compile backend/__init__.py && echo "[init-fix] __init__.py reescrito y compilado OK" || { echo "[init-fix] py_compile FAIL"; exit 4; }
echo "[init-fix] Listo."
