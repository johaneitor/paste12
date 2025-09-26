#!/usr/bin/env bash
set -euo pipefail

backup() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  local ts="$(date -u +%Y%m%d-%H%M%SZ)"
  cp -f "$f" "$f.$ts.bak"
  echo "[backup] $f.$ts.bak"
}

# 1) backend/__init__.py (factory segura)
backup backend/__init__.py
cat > backend/__init__.py <<'PY'
from __future__ import annotations

import os
from flask import Flask, jsonify
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy

# SQLAlchemy global (sin inicializar)
db = SQLAlchemy()

def _normalize_db_uri(uri: str | None) -> str | None:
    if not uri:
        return None
    if uri.startswith("postgres://"):
        uri = uri.replace("postgres://", "postgresql://", 1)
    return uri

def create_app() -> Flask:
    # sin static_folder para evitar servir HTML accidentalmente desde Flask
    app = Flask(__name__, static_folder=None)

    # --- Config DB --- 
    uri = _normalize_db_uri(os.getenv("DATABASE_URL") or os.getenv("SQLALCHEMY_DATABASE_URI"))
    if uri:
        app.config["SQLALCHEMY_DATABASE_URI"] = uri
    app.config.setdefault("SQLALCHEMY_TRACK_MODIFICATIONS", False)

    # --- CORS ---
    CORS(app, resources={r"/api/*": {"origins": "*"}})

    # --- DB init (si hay URI, SQLAlchemy se inicializa) ---
    db.init_app(app)

    # --- Health SIEMPRE disponible ---
    @app.get("/api/health")
    def health():
        # usa un tag de versión explícito para saber qué build corre
        return jsonify(ok=True, api=True, ver="factory-v5")

    # --- Intentar registrar tus rutas reales ---
    try:
        from backend.routes import api_bp  # type: ignore
        app.register_blueprint(api_bp, url_prefix="/api")
    except Exception as exc:
        # Fallback local y autocontenible (NUNCA referencia variables no definidas)
        @app.route("/api/notes", methods=["GET", "POST", "HEAD", "OPTIONS"])
        def _api_unavailable():
            return jsonify(error="API routes not loaded", detail=str(exc)), 500

    return app
PY

# 2) wsgi.py (exporta 'application' y alias 'app')
backup wsgi.py
cat > wsgi.py <<'PY'
from backend import create_app  # type: ignore
application = create_app()
# alias por compatibilidad con algunas plataformas
app = application
PY

python -m py_compile backend/__init__.py wsgi.py && echo "[lock] py_compile OK"

echo "Listo. Usa este Start Command en Render:"
echo "  gunicorn wsgi:application --chdir /opt/render/project/src -w \${WEB_CONCURRENCY:-2} -k gthread --threads \${THREADS:-4} --timeout \${TIMEOUT:-120} -b 0.0.0.0:\$PORT"
