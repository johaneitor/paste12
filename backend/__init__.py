import os
from typing import Optional
from flask import Flask, jsonify
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy

# SQLAlchemy en módulo (evita circular import si routes importa models)
db = SQLAlchemy()

def _normalize_db_url(raw: Optional[str]) -> Optional[str]:
    if not raw:
        return None
    # render/heroku style
    if raw.startswith("postgres://"):
        return "postgresql://" + raw[len("postgres://"):]
    return raw

def create_app() -> Flask:
    app = Flask(__name__)

    # Config DB (permitir boot sin DB para health/HTML)
    raw = (
        os.environ.get("DATABASE_URL")
        or os.environ.get("POSTGRES_URL")
        or os.environ.get("POSTGRESQL_ADDON_URI")
        or os.environ.get("POSTGRESQL_URL")
    )
    uri = _normalize_db_url(raw)
    if uri:
        app.config["SQLALCHEMY_DATABASE_URI"] = uri
    else:
        # arranca sin DB para que /api/health responda 200
        app.config["SQLALCHEMY_DATABASE_URI"] = "sqlite:///:memory:"

    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

    CORS(app)
    db.init_app(app)

    # health provisional (se sobrescribe si cargan las rutas reales)
    @app.get("/api/health")
    def _health_boot():
        return jsonify(ok=True, api=False, ver="factory-v3")

    # Intentar registrar blueprint real de la API
    try:
        from .routes import api_bp  # type: ignore
        app.register_blueprint(api_bp, url_prefix="/api")

        @app.get("/api/health")
        def _health_ok():
            return jsonify(ok=True, api=True, ver="factory-v3")
    except Exception as e:
        # Fallback limpio si no cargó el blueprint
        @app.route("/api/notes", methods=["GET", "POST", "OPTIONS", "PUT", "DELETE"])
        @app.route("/api/notes/<path:_rest>", methods=["GET", "POST", "OPTIONS", "PUT", "DELETE"])
        def _api_unavailable(_rest=None):
            return jsonify(error="API routes not loaded", detail=str(e)), 500

    # Servir index (simple) para no romper el root si el frontend está en /frontend/index.html
    @app.get("/")
    def _index_html():
        try:
            root = os.path.dirname(os.path.abspath(__file__))
            path = os.path.normpath(os.path.join(root, "..", "frontend", "index.html"))
            with open(path, "r", encoding="utf-8") as fh:
                return fh.read(), 200, {"Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store"}
        except Exception:
            return "<!doctype html><meta charset='utf-8'><title>Paste12</title><h1>Paste12</h1>", 200, {"Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store"}

    return app
