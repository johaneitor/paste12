#!/usr/bin/env bash
set -euo pipefail
F="backend/__init__.py"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
[[ -f "$F" ]] && cp -f "$F" "$F.$TS.bak" && echo "[backup] $F.$TS.bak"

cat > "$F" <<'PY'
from __future__ import annotations
import os
from flask import Flask, jsonify
from flask_sqlalchemy import SQLAlchemy
from flask_cors import CORS
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

db = SQLAlchemy()
limiter = Limiter(get_remote_address, default_limits=["600/hour", "120/minute"])

def _normalize_db_url(url: str | None) -> str | None:
    if not url: return None
    if url.startswith("postgres://"):
        url = url.replace("postgres://", "postgresql+psycopg2://", 1)
    return url

def create_app() -> Flask:
    app = Flask(__name__, static_folder=None)

    # --- Config DB
    db_url = _normalize_db_url(os.environ.get("DATABASE_URL") or os.environ.get("DATABASE_URI"))
    if db_url:
        app.config["SQLALCHEMY_DATABASE_URI"] = db_url
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

    # --- CORS (completo para /api/*)
    CORS(
        app,
        resources={r"/api/*": {"origins": "*"}},
        supports_credentials=False,
        allow_headers=["Content-Type"],
        methods=["GET", "POST", "HEAD", "OPTIONS"],
        max_age=86400,
    )

    # --- Init
    db.init_app(app)
    limiter.init_app(app)

    # --- Registrar API real o fallback
    api_loaded = False
    try:
        from .routes import api_bp  # debe existir
        app.register_blueprint(api_bp)
        api_loaded = True
    except Exception:
        # Fallback mínimo para no romper la app completa
        from flask import Blueprint, request
        fb = Blueprint("api_fallback", __name__)

        @fb.route("/api/notes", methods=["GET","POST","HEAD","OPTIONS"])
        def _api_unavailable():
            return jsonify(error="API routes not loaded"), 500

        app.register_blueprint(fb)
        api_loaded = False

    @app.get("/api/health")
    def health():
        return jsonify(ok=True, api=bool(api_loaded), ver="factory-v7")

    # --- Asegurar cabeceras de preflight siempre presentes
    @app.after_request
    def _ensure_cors(resp):
        resp.headers.setdefault("Access-Control-Allow-Origin", "*")
        resp.headers.setdefault("Access-Control-Allow-Methods", "GET, POST, HEAD, OPTIONS")
        resp.headers.setdefault("Access-Control-Allow-Headers", "Content-Type")
        resp.headers.setdefault("Access-Control-Max-Age", "86400")
        return resp

    return app
PY

python - <<'PY'
import py_compile; py_compile.compile("backend/__init__.py", doraise=True)
print("py_compile __init__ OK")
PY
echo "Listo."
