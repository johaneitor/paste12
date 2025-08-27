from __future__ import annotations
import os
from flask import Flask
from flask_sqlalchemy import SQLAlchemy

# SQLAlchemy global del paquete (lo usan los modelos)
db = SQLAlchemy()

def create_app() -> Flask:
    app = Flask(__name__)

    # Config DB (Render suele exponer DATABASE_URL; si no, sqlite)
    app.config["SQLALCHEMY_DATABASE_URI"] = os.environ.get("DATABASE_URL", "sqlite:///app.db")
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

    # Inicializar db
    db.init_app(app)

    # Intentar registrar blueprint oficial si existe
    try:
        from .routes import bp as api_bp  # noqa
        app.register_blueprint(api_bp, url_prefix="/api")
    except Exception:
        # Si no existe backend.routes, no hacemos nada aquí
        pass

    return app
