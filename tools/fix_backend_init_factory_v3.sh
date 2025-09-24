#!/usr/bin/env bash
set -euo pipefail
TS="$(date -u +%Y%m%d-%H%M%SZ)"
TGT="backend/__init__.py"
[[ -f "$TGT" ]] && cp -f "$TGT" "${TGT}.${TS}.bak" && echo "[init-factory] Backup: ${TGT}.${TS}.bak"

cat > "$TGT" <<'PY'
import os
from flask import Flask, jsonify, make_response
from flask_sqlalchemy import SQLAlchemy
from flask_cors import CORS

db = SQLAlchemy()

def _normalize_db_url(url: str) -> str:
    if not url:
        return ""
    # Render a veces pasa postgres:// → normalizamos a postgresql://
    return url.replace("postgres://", "postgresql://", 1)

def create_app():
    app = Flask(__name__, static_folder=None)

    uri = _normalize_db_url(os.getenv("DATABASE_URL", ""))
    if not uri:
        # Fallback local para py_compile / scripts
        uri = "sqlite:///local.db"
    app.config["SQLALCHEMY_DATABASE_URI"] = uri
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

    # CORS sólo para /api/*
    CORS(app, resources={r"/api/*": {"origins": "*"}})

    # Inicializar SQLAlchemy
    db.init_app(app)

    # Registrar API (si está) — se importa dentro para evitar ciclos
    try:
        from .routes import api_bp  # type: ignore
        app.register_blueprint(api_bp, url_prefix="/api")
    except Exception as e:
        # Si la API falla al importar, dejamos health y un mensaje explícito
        @app.get("/api/notes")
        def _api_unavailable():
            return jsonify(error="API routes not loaded", detail=str(e)), 500

    # Registrar frontend blueprint (sirve index/terms/privacy)
    try:
        from .front_serve import front_bp  # type: ignore
        app.register_blueprint(front_bp)
    except Exception:
        pass

    @app.get("/api/health")
    def health():
        # ok=true siempre que el proceso esté vivo; api=true si el blueprint de API cargó
        api_ok = any(r.rule.startswith("/api/notes") for r in app.url_map.iter_rules())
        return jsonify(ok=True, api=api_ok, ver="factory-v3")

    # Preflight manual para /api/notes (CORS)
    @app.route("/api/notes", methods=["OPTIONS"])
    def notes_options():
        resp = make_response("", 204)
        h = resp.headers
        h["Access-Control-Allow-Origin"] = "*"
        h["Access-Control-Allow-Methods"] = "GET, POST, HEAD, OPTIONS"
        h["Access-Control-Allow-Headers"] = "Content-Type"
        h["Access-Control-Max-Age"] = "86400"
        return resp

    return app
PY

echo "[init-factory] backend/__init__.py actualizado"
