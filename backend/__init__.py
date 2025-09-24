# -*- coding: utf-8 -*-
import os
from flask import Flask, jsonify
from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()

def _normalize_db_url(url: str) -> str:
    if not url:
        return "sqlite:////tmp/paste12.db"
    u = url.strip()
    # Render / Heroku style
    if u.startswith("postgres://"):
        u = u.replace("postgres://", "postgresql+psycopg2://", 1)
    if u.startswith("postgresql://"):
        # asegurar driver explícito
        if "postgresql+psycopg2://" not in u:
            u = u.replace("postgresql://", "postgresql+psycopg2://", 1)
    return u

def create_app():
    app = Flask(__name__)

    raw = (
        os.getenv("DATABASE_URL")
        or os.getenv("RENDER_DATABASE_URL")
        or os.getenv("POSTGRES_URL")
        or ""
    )
    app.config["SQLALCHEMY_DATABASE_URI"] = _normalize_db_url(raw)
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

    # init DB (no toca la red hasta que se use sesión)
    db.init_app(app)

    # health lightweight para el boot de Render
    @app.get("/api/health")
    def health():
        return jsonify(ok=True, api=True, ver="factory-v2")

    # registrar rutas después de init_app para evitar import cíclico
    try:
        from .routes import bp as api_bp  # noqa
        app.register_blueprint(api_bp, url_prefix="/api")
    except Exception:
        # si todavía no existen rutas, seguimos; health ya responde
        pass

    return app

# Export opcional por compatibilidad con gunicorn module:app
app = create_app()
