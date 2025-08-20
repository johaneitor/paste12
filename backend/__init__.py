import os
from datetime import datetime, timezone
from flask import Flask, send_from_directory
from flask_sqlalchemy import SQLAlchemy
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from flask_cors import CORS
from sqlalchemy import text

try:
    from flask_compress import Compress
except Exception:  # lib opcional
    Compress = None

# Extensiones exportadas para: from . import db, limiter
db = SQLAlchemy()
limiter = Limiter(key_func=get_remote_address, default_limits=[])

def _database_uri() -> str:
    uri = os.getenv("DATABASE_URL") or os.getenv("SQLALCHEMY_DATABASE_URI")
    if not uri:
        os.makedirs("instance", exist_ok=True)
        return "sqlite:///instance/production.db"
    # Render a veces da postgres:// (depre)
    return uri.replace("postgres://", "postgresql+psycopg2://")

def create_app():
    app = Flask(__name__, static_folder="frontend", static_url_path="")

    # -- Registrar rutas del frontend (inline, sin decoradores globales) --
    def _register_frontend(app):
        @app.get('/favicon.ico')
        def _favicon():
            return send_from_directory(app.static_folder, 'favicon.svg', mimetype='image/svg+xml')

        @app.get('/ads.txt')
        def _ads():
            return send_from_directory(app.static_folder, 'ads.txt', mimetype='text/plain')

        @app.route('/')
        def _index():
            return send_from_directory(app.static_folder, 'index.html')

        @app.route('/<path:path>')
        def _static_any(path):
            # Evitar colisión con API:
            if path.startswith('api/'):
                from flask import abort
                return abort(404)
            import os
            full = os.path.join(app.static_folder, path)
            if os.path.isfile(full):
                return send_from_directory(app.static_folder, path)
            # Fallback SPA
            return send_from_directory(app.static_folder, 'index.html')

    if '_register_frontend' not in locals():
        pass  # por si re-ejecución
    _register_frontend(app)
    app.config.update(
        SQLALCHEMY_DATABASE_URI=_database_uri(),
        SQLALCHEMY_TRACK_MODIFICATIONS=False,
    )

    # Pooling/SSL recomendado para Postgres en Render
    if app.config["SQLALCHEMY_DATABASE_URI"].startswith("postgresql"):
        app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {
            "pool_pre_ping": True,
            "pool_recycle": 300,
            "pool_size": 5,
            "max_overflow": 10,
        }
    else:  # SQLite local
        app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {
            "connect_args": {"check_same_thread": False}
        }

    CORS(app)
    if Compress:
        Compress(app)

    db.init_app(app)
    limiter.init_app(app)

    # Migración mínima compatible con SQLAlchemy 2.x
    with app.app_context():
        db.create_all()
        try:
            with db.engine.begin() as conn:
                conn.execute(text("SELECT 1"))
        except Exception as e:
            app.logger.warning(f"migrate_min: {e}")

    # ---- Rutas estáticas básicas (deben ir DESPUÉS de crear app) ----
    @app.get("/favicon.ico")
    def _favicon():
        return send_from_directory(app.static_folder, "favicon.svg", mimetype="image/svg+xml")

    @app.get("/ads.txt")
    def _ads_txt():
        return send_from_directory(app.static_folder, "ads.txt", mimetype="text/plain")

    @app.route("/")
    def index():
        return send_from_directory(app.static_folder, "index.html")

    @app.get("/healthz")
    def _healthz():
        return {"ok": True, "ts": datetime.now(timezone.utc).isoformat()}

    # API
    from . import routes  # noqa: WPS433
    app.register_blueprint(routes.bp)
    # --- Rutas estáticas del frontend (Blueprint) ---
    try:
        from .static_routes import bp as static_bp
        app.register_blueprint(static_bp)
    except Exception as _e:
        app.logger.error(f"static_bp register failed: {_e}")


    return app
