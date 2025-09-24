from __future__ import annotations
import os
from flask import Flask, jsonify, send_from_directory
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()

def _normalize_db_uri(uri: str) -> str:
    if uri.startswith("postgres://"):
        return uri.replace("postgres://", "postgresql+psycopg2://", 1)
    if uri.startswith("postgresql://"):
        return uri.replace("postgresql://", "postgresql+psycopg2://", 1)
    return uri

def create_app() -> Flask:
    app = Flask(__name__, static_folder="../frontend", static_url_path="/")
    uri = os.getenv("DATABASE_URL") or os.getenv("DATABASE_URI") or "sqlite:///local.db"
    app.config["SQLALCHEMY_DATABASE_URI"] = _normalize_db_uri(uri)
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    app.config["JSON_SORT_KEYS"] = False

    # DB + CORS
    db.init_app(app)
    CORS(app, resources={r"/api/*": {"origins": "*"}}, expose_headers=["Link"], max_age=86400)

    # Health temprano (no toca DB)
    @app.get("/api/health")
    def health():
        return jsonify(ok=True, api=True, ver="clean-init-v1")

    # Registrar rutas DESPUÉS de init_app para evitar ciclos
    from .routes import api_bp  # import local para no formar ciclo
    app.register_blueprint(api_bp)

    # Index estático
    @app.get("/")
    def index_page():
        return send_from_directory(app.static_folder, "index.html")

    # Crear tablas si no existen (no rompe en Postgres si ya están)
    try:
        with app.app_context():
            db.create_all()
    except Exception:
        # No hacemos ruido en prod (p.ej. roles limitados o migraciones externas)
        pass

    return app

# Exponer WSGI por compatibilidad con gunicorn wsgi:application
app = create_app()
