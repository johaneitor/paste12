# backend/__init__.py — clean reset: DB + Limiter + API + static frontend
import os
from datetime import timezone
from flask import Flask, send_from_directory, abort
from flask_sqlalchemy import SQLAlchemy
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from sqlalchemy import text

# Extensiones como singletons a nivel módulo (para 'from backend import db, limiter')
db = SQLAlchemy()
limiter = Limiter(key_func=get_remote_address, default_limits=[])

def _abs(path: str) -> str:
    return os.path.abspath(os.path.join(os.path.dirname(__file__), path))

def _build_database_uri() -> str:
    url = os.getenv("DATABASE_URL")
    if not url:
        os.makedirs(_abs("../instance"), exist_ok=True)
        return "sqlite:///" + _abs("../instance/production.db")
    if url.startswith(("postgres://", "postgresql://")) and "sslmode=" not in url:
        url += ("&" if "?" in url else "?") + "sslmode=require"
    return url

def create_app():
    static_folder = _abs("../frontend")
    app = Flask(__name__, static_folder=static_folder, static_url_path="")

    # ---- Config DB (con keepalive para Render) ----
    app.config["SQLALCHEMY_DATABASE_URI"] = _build_database_uri()
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {
        "pool_pre_ping": True,
        "pool_recycle": 280,
    }

    # Inicializar extensiones
    db.init_app(app)
    limiter.init_app(app)

    # Migración mínima (SQLAlchemy 2.x-safe)
    with app.app_context():
        try:
            from . import models  # asegura que los modelos se registren
            db.create_all()
            with db.engine.begin() as conn:
                conn.execute(text("SELECT 1"))
        except Exception as e:
            app.logger.warning(f"migrate_min: {e}")

    # Registrar API
    try:
        from .routes import bp as api_bp
        app.register_blueprint(api_bp, url_prefix="/api")
    except Exception as e:
        app.logger.error(f"No se pudo registrar blueprint API: {e}")

    # Rutas de frontend (idempotentes, sin decoradores)
    def _register_frontend(app):
        sf = app.static_folder

        # /favicon.ico
        if "/favicon.ico" not in {r.rule for r in app.url_map.iter_rules()}:
            app.add_url_rule(
                "/favicon.ico",
                endpoint="static_favicon",
                view_func=lambda: send_from_directory(sf, "favicon.svg", mimetype="image/svg+xml"),
            )

        # /ads.txt
        if "/ads.txt" not in {r.rule for r in app.url_map.iter_rules()}:
            app.add_url_rule(
                "/ads.txt",
                endpoint="static_ads",
                view_func=lambda: send_from_directory(sf, "ads.txt", mimetype="text/plain"),
            )

        # /
        if "/" not in {r.rule for r in app.url_map.iter_rules()}:
            app.add_url_rule(
                "/",
                endpoint="static_root",
                view_func=lambda: send_from_directory(sf, "index.html"),
            )

        # Fallback SPA y archivos estáticos
        if "static_any" not in app.view_functions:
            def static_any(path):
                if path.startswith("api/"):
                    return abort(404)
                full = os.path.join(sf, path)
                if os.path.isfile(full):
                    return send_from_directory(sf, path)
                return send_from_directory(sf, "index.html")
            app.add_url_rule("/<path:path>", endpoint="static_any", view_func=static_any)

    _register_frontend(app)
    # Enforce cap al boot (una vez) si está habilitado
    try:
        from .tasks import enforce_global_cap as _egc
        if os.getenv("ENFORCE_CAP_ON_BOOT", "1") == "1":
            _egc(app)
    except Exception as _e:
        try:
            app.logger.warning(f"enforce_cap_on_boot: {_e}")
        except Exception:
            pass

    
    # --- Registrar API blueprint ---
    try:
        from .routes import bp as api_bp
        app.register_blueprint(api_bp)
        app.logger.info("API blueprint registrado")
    except Exception as e:
        app.logger.error(f"No se pudo registrar blueprint API: {e}")

    # --- Rutas estáticas idempotentes + SPA; NO capturar /api/*
    try:
        existing = {r.rule for r in app.url_map.iter_rules()}
        if "/favicon.ico" not in existing:
            app.add_url_rule("/favicon.ico","static_favicon", view_func=lambda: send_from_directory(app.static_folder, "favicon.svg", mimetype="image/svg+xml"))
        if "/ads.txt" not in existing:
            app.add_url_rule("/ads.txt","static_ads", view_func=lambda: send_from_directory(app.static_folder, "ads.txt", mimetype="text/plain"))
        if "/" not in existing:
            app.add_url_rule("/","static_root", view_func=lambda: send_from_directory(app.static_folder, "index.html"))
        if "static_any" not in app.view_functions:
            import os
            def static_any(path):
                if path.startswith("api/"):
                    from flask import abort
                    return abort(404)
                full = os.path.join(app.static_folder, path)
                from flask import send_from_directory
                import os as _os
                if _os.path.isfile(full):
                    return send_from_directory(app.static_folder, path)
                return send_from_directory(app.static_folder, "index.html")
            app.add_url_rule("/<path:path>", "static_any", static_any)
    except Exception as e:
        app.logger.warning(f"Rutas estáticas: {e}")
        
        try:
            enforce_cap_on_boot(app)
        except Exception as e:
            app.logger.warning(f"enforce_cap_on_boot: {e}")
    return app


def migrate_min(app):
    from . import db
    with app.app_context():
        try:
            db.create_all()
            with db.engine.begin() as conn:
                conn.execute(text("CREATE INDEX IF NOT EXISTS ix_note_expires_at ON note (expires_at)"))
                conn.execute(text("CREATE INDEX IF NOT EXISTS ix_note_exp_ts ON note (expires_at, timestamp)"))
                conn.execute(text("CREATE INDEX IF NOT EXISTS ix_note_ts_desc ON note (timestamp DESC)"))
        except Exception as e:
            try:
                app.logger.warning(f"migrate_min: {e}")
            except Exception:
                print("migrate_min warn:", e)
