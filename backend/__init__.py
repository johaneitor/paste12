from __future__ import annotations
import os
from flask_sqlalchemy import SQLAlchemy
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

# Objetos de extensión exportados por el paquete
db = SQLAlchemy()
limiter = Limiter(key_func=get_remote_address, default_limits=[])

def init_extensions(app):
    # Config mínima de DB y Limiter
    app.config.setdefault("SQLALCHEMY_DATABASE_URI", os.environ.get("DATABASE_URL", "sqlite:///app.db"))
    app.config.setdefault("SQLALCHEMY_TRACK_MODIFICATIONS", False)
    app.config.setdefault("RATELIMIT_STORAGE_URI", os.environ.get("RATELIMIT_STORAGE_URI", "memory://"))
    # Inicializar extensiones
    db.init_app(app)
    limiter.init_app(app)
