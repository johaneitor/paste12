from __future__ import annotations
import os
from flask import Flask
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
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


# --- DB hardening helpers (idempotente) ---
def _normalize_database_url(url: str|None):
    if not url:
        return url
    # Corrige postgres:// -> postgresql://
    if url.startswith("postgres://"):
        url = "postgresql://" + url[len("postgres://"):]
    # Asegura sslmode=require si no está presente
    if "sslmode=" not in url:
        sep = "&" if "?" in url else "?"
        url = f"{url}{sep}sslmode=require"
    return url

def apply_engine_hardening(app):
    # Motor con pre_ping y recycle para evitar EOF/idle disconnects
    app.config.setdefault("SQLALCHEMY_ENGINE_OPTIONS", {})
    opts = app.config["SQLALCHEMY_ENGINE_OPTIONS"]
    opts.setdefault("pool_pre_ping", True)
    opts.setdefault("pool_recycle", 300)
    opts.setdefault("pool_size", 5)
    opts.setdefault("max_overflow", 10)
    opts.setdefault("pool_timeout", 30)
    app.config["SQLALCHEMY_ENGINE_OPTIONS"] = opts


# create_all con retry para evitar fallos transitorios de red/SSL
def _retry_create_all(db, app, tries=5):
    import time
    for i in range(tries):
        try:
            with app.app_context():
                db.create_all()
            return True
        except Exception as e:
            # backoff simple
            time.sleep(1 + i)
    return False

try:
    _retry_create_all(db, app)
except Exception:
    pass

# paste12 limiter init
limiter = Limiter(key_func=get_remote_address, default_limits=[])

