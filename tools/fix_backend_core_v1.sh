#!/usr/bin/env bash
set -euo pipefail

backup() { [[ -f "$1" ]] && cp -f "$1" "$1.$(date -u +%Y%m%d-%H%M%SZ).bak" || true; }

mkdir -p backend

# 1) backend/db.py : fuente única del objeto db
if [[ ! -f backend/db.py ]]; then
  cat > backend/db.py <<'PY'
from flask_sqlalchemy import SQLAlchemy
# Objeto global, sin importar 'backend' para evitar ciclos
db = SQLAlchemy()
PY
  echo "[corefix] creado backend/db.py"
else
  echo "[corefix] backend/db.py ya existe (ok)"
fi

# 2) backend/__init__.py : factoría + reexport de db + health
backup backend/__init__.py
cat > backend/__init__.py <<'PY'
from __future__ import annotations
import os
from flask import Flask, jsonify
from flask_cors import CORS

# Reexportamos db desde un módulo que NO importa 'backend'
from .db import db

def _normalize_db_url(url: str) -> str:
    if not url:
        return ""
    # Render suele dar postgres://; SQLAlchemy 2.x espera postgresql+psycopg2://
    if url.startswith("postgres://"):
        url = url.replace("postgres://", "postgresql+psycopg2://", 1)
    return url

def create_app() -> Flask:
    app = Flask(__name__)

    db_url = _normalize_db_url(os.getenv("DATABASE_URL", ""))
    app.config["SQLALCHEMY_DATABASE_URI"] = db_url or "sqlite:///local.db"
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

    # CORS sólo para /api/*
    CORS(app, resources={r"/api/*": {"origins": "*"}})

    # Inicializamos pool/DB
    db.init_app(app)

    # Health muy temprano (para boot checks internos de Render)
    @app.get("/api/health")
    def health():
        return jsonify(ok=True, api=True, ver="corefix-v1")

    # Registramos rutas *después* de tener app+db listos para evitar ciclos
    try:
        from .routes import bp as api_bp  # noqa: WPS433
        app.register_blueprint(api_bp)
    except Exception as e:
        # No frenamos el arranque para que /api/health siga respondiendo
        # y podamos ver los errores en logs.
        app.logger.error("No se pudo registrar rutas: %r", e)

    return app

# Export para gunicorn/WSGI shims
app = create_app()
PY
echo "[corefix] backend/__init__.py actualizado"

# 3) Validación rápida
python -m py_compile backend/__init__.py
echo "[corefix] py_compile OK (backend/__init__.py)"

# 4) Mensaje final
cat <<MSG
Listo. Siguiente:
  - Deploy en Render (mismo Start Command):
    gunicorn wsgi:application --chdir /opt/render/project/src -w \${WEB_CONCURRENCY:-2} -k gthread --threads \${THREADS:-4} --timeout \${TIMEOUT:-120} -b 0.0.0.0:\$PORT
  - Luego corre el smoke:
    tools/smoke_after_corefix_v1.sh "https://paste12-rmsk.onrender.com" "/sdcard/Download"
MSG
