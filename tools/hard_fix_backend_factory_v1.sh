#!/usr/bin/env bash
set -euo pipefail

TARGET="backend/__init__.py"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
BAK="${TARGET}.${TS}.bak"

[[ -f "$TARGET" ]] || { echo "ERROR: falta $TARGET"; exit 1; }
cp -f "$TARGET" "$BAK"
echo "[backup] $BAK"

python - <<'PY'
import os, io, textwrap

code = r'''
from __future__ import annotations

import os
from typing import Tuple, Optional

from flask import Flask, jsonify, request
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy

# SQLAlchemy singleton exportado para "from backend import db"
db = SQLAlchemy()


def _normalize_db_url(url: str) -> str:
    if not url:
        return url
    # Normaliza drivers
    if url.startswith("postgres://"):
        url = "postgresql+psycopg2://" + url[len("postgres://"):]
    elif url.startswith("postgresql://") and "+psycopg2" not in url:
        url = url.replace("postgresql://", "postgresql+psycopg2://", 1)
    return url


def _safe_register_routes(app: Flask) -> Tuple[bool, Optional[str]]:
    """
    Intenta cargar y registrar rutas del módulo backend.routes de forma segura.

    Estrategias:
      1) Si backend.routes expone 'bp' (Blueprint), se registra.
      2) Si expone 'register_routes(app)', se invoca.
      3) Si expone 'attach(app)', se invoca.

    Devuelve (ok, err_str).
    """
    try:
        import importlib
        routes = importlib.import_module("backend.routes")

        if hasattr(routes, "bp"):
            app.register_blueprint(routes.bp)
            return True, None

        if hasattr(routes, "register_routes") and callable(routes.register_routes):
            routes.register_routes(app)
            return True, None

        if hasattr(routes, "attach") and callable(routes.attach):
            routes.attach(app)
            return True, None

        # Si no encontramos ninguna convención conocida, error explícito:
        return False, "backend.routes no expone bp/register_routes/attach"
    except Exception as e:  # pragma: no cover
        return False, f"{type(e).__name__}: {e}"


def _api_unavailable_factory(err_text: str):
    """
    Fallback estable para /api/notes. No captura variables libres 'e',
    usa el texto ya materializado.
    """
    def _handler():
        if request.method == "OPTIONS":
            # Devolvemos 204 para que CORS/options pasen igual
            return ("", 204)
        return jsonify(error="API routes not loaded", detail=err_text or "unknown"), 500
    return _handler


def create_app() -> Flask:
    app = Flask(__name__)

    # CORS básico sobre /api/* (orígenes abiertos; ajustar si hace falta)
    CORS(app, resources={r"/api/*": {"origins": "*"}}, supports_credentials=False)

    # Config DB
    db_url = _normalize_db_url(os.environ.get("DATABASE_URL", "").strip())
    if db_url:
        app.config["SQLALCHEMY_DATABASE_URI"] = db_url
    # tuning sano de pool
    app.config.setdefault("SQLALCHEMY_ENGINE_OPTIONS", {
        "pool_pre_ping": True,
        "pool_recycle": 300,
        "pool_size": 5,
        "max_overflow": 5,
    })
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

    # Inicializa SQLAlchemy
    db.init_app(app)

    # Intenta registrar rutas reales
    ok, err = _safe_register_routes(app)
    app.config["API_ROUTES_OK"] = bool(ok)
    app.config["API_IMPORT_ERROR"] = err or ""

    # Health siempre disponible
    @app.route("/api/health", methods=["GET"])
    def _health():
        return jsonify(ok=True, api=bool(app.config.get("API_ROUTES_OK")), ver="factory-v4")

    # Fallback /api/notes solo si no pudimos registrar rutas
    if not ok:
        app.add_url_rule(
            "/api/notes",
            "api_notes_fallback",
            _api_unavailable_factory(app.config.get("API_IMPORT_ERROR", "")),
            methods=["GET", "POST", "HEAD", "OPTIONS"],
        )

    # 404 JSON para /api/* (opcional pero útil al auditar)
    @app.errorhandler(404)
    def _not_found(e):  # pragma: no cover
        if request.path.startswith("/api/"):
            return jsonify(error="not found", path=request.path), 404
        # fuera de /api lo maneja el front
        return e, 404

    return app
'''

p = "backend/__init__.py"
io.open(p, "w", encoding="utf-8").write(code)
print("[fix] backend/__init__.py reescrito (factory estable)")
PY

python -m py_compile backend/__init__.py && echo "[py_compile] OK"

echo "Listo. Ahora haz deploy en Render y probamos."
