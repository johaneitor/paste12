from __future__ import annotations

from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()

def _db_uri() -> str:
    import os, re, pathlib
    uri = os.getenv("DATABASE_URL")
    if uri:
        # postgres -> postgresql+psycopg
        uri = re.sub(r"^postgres://", "postgresql+psycopg://", uri)
        # postgresql:// -> postgresql+psycopg:// si falta driver
        if uri.startswith("postgresql://") and "+psycopg://" not in uri:
            uri = uri.replace("postgresql://", "postgresql+psycopg://", 1)
        return uri
    # Fallback SQLite local
    db_path = pathlib.Path("data/app.db").resolve()
    return f"sqlite:///{db_path}"

def create_app():
    from flask import Flask
    app = Flask(__name__)
    app.config["SQLALCHEMY_DATABASE_URI"] = _db_uri()
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {
        "pool_pre_ping": True,
        "pool_recycle": 280,
    }
    db.init_app(app)

    # Registrar blueprint después de init_app para evitar ciclos
    from .routes import api as api_blueprint  # import diferido
    app.register_blueprint(api_blueprint)

    # Crear tablas si no existen
    with app.app_context():
        db.create_all()

    return app
