import secrets
from zoneinfo import ZoneInfo
from apscheduler.schedulers.background import BackgroundScheduler
from flask import Flask, send_from_directory, request, make_response, send_from_directory
from datetime import datetime, timezone, timedelta
import os
from pathlib import Path
from flask import Flask, send_from_directory, send_from_directory
from flask_sqlalchemy import SQLAlchemy
from flask_cors import CORS
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

# SQLAlchemy singleton del paquete (otros módulos hacen "from . import db")
db = SQLAlchemy()

def ensure_client_cookie(app):
    @app.before_request
    def _p12_cookie():
        # si ya hay cookie, no hacemos nada
        if request.cookies.get('p12'): return
        # colocamos cookie en la primera respuesta
        @app.after_request
        def _set_cookie(resp):
            try:
                if not request.cookies.get('p12'):
                    tok = secrets.token_hex(16)
                    resp.set_cookie('p12', tok, max_age=60*60*24*365, httponly=False, samesite='Lax')
            except Exception:
                pass
            return resp
        return None

def create_app():
    @app.get('/favicon.ico')
    def _favicon():
        return send_from_directory(app.static_folder, 'favicon.svg', mimetype='image/svg+xml')

    # --- Flask + estáticos del frontend ---
    ROOT = Path(__file__).resolve().parents[1]
    app = Flask(
        __name__,
        static_folder=str(ROOT / "frontend"),
        static_url_path=""  # sirve frontend en /
    )

    # --- CORS (API pública) ---
    CORS(app, resources={r"/api/*": {"origins": "*"}})

    # --- Rate limiter ---
    limiter = Limiter(
        key_func=get_remote_address,
        app=app,
        storage_uri=os.getenv("RATELIMIT_STORAGE_URL", "memory://"),
        default_limits=[os.getenv("RATE_LIMIT", "200/minute")],
    )

    # --- Base de datos (Render Postgres / fallback SQLite) ---
    db_url = os.getenv("DATABASE_URL")
    if db_url:
        # Render aún expone a veces postgres:// → normaliza a postgresql://
        if db_url.startswith("postgres://"):
            db_url = "postgresql://" + db_url[len("postgres://"):]
        # En Render es buena práctica forzar SSL
        if db_url.startswith("postgresql://") and "sslmode=" not in db_url:
            sep = "&" if "?" in db_url else "?"
            db_url = db_url + f"{sep}sslmode=require"
        app.config["SQLALCHEMY_DATABASE_URI"] = db_url
    else:
        # Local/Termux: usa SQLite en instance/
        os.makedirs(app.instance_path, exist_ok=True)
        app.config["SQLALCHEMY_DATABASE_URI"] = "sqlite:///" + str(Path(app.instance_path) / "production.db")

    # Engine/pool robusto para Postgres gestionado (evita SSL EOF)
    app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {
        "pool_pre_ping": True,
        "pool_recycle": 300,   # segundos
        "pool_timeout": 30,
        "pool_size": 5,
        "max_overflow": 10,
    }
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

    # Inicializa ORM
    db.init_app(app)
    limiter.init_app(app)

    # Crea tablas si no existen
    with app.app_context():
        db.create_all()

    # Blueprints de API
    from . import routes
    app.register_blueprint(routes.bp)

    # Ruta raíz: devuelve el frontend
    @app.route("/")
    def index():
        return send_from_directory(app.static_folder, "index.html")

    # Healthcheck para Render
    @app.get("/healthz")
    def healthz():
        return {"ok": True}

    
    with app.app_context():
        db.create_all()
        try:
            from sqlalchemy import text
            eng = db.engine
            # Crea LikeLog / ReportLog si no existen (por seguridad)
            eng.execute(text('''
            CREATE TABLE IF NOT EXISTS like_log (
              id SERIAL PRIMARY KEY,
              note_id INTEGER NOT NULL REFERENCES note(id) ON DELETE CASCADE,
              fingerprint VARCHAR(128) NOT NULL,
              created_at TIMESTAMPTZ DEFAULT NOW()
            );
            '''))
            eng.execute(text('''
            CREATE TABLE IF NOT EXISTS report_log (
              id SERIAL PRIMARY KEY,
              note_id INTEGER NOT NULL REFERENCES note(id) ON DELETE CASCADE,
              fingerprint VARCHAR(128) NOT NULL,
              created_at TIMESTAMPTZ DEFAULT NOW()
            );
            '''))
            # UNIQUE constraints si faltan
            eng.execute(text('''
            DO $$
            BEGIN
              IF NOT EXISTS (
                SELECT 1 FROM pg_constraint c
                JOIN pg_class t ON c.conrelid=t.oid
                WHERE t.relname='like_log' AND c.conname='uq_like_note_fp'
              ) THEN
                ALTER TABLE like_log ADD CONSTRAINT uq_like_note_fp UNIQUE (note_id, fingerprint);
              END IF;
            END$$;
            '''))
            eng.execute(text('''
            DO $$
            BEGIN
              IF NOT EXISTS (
                SELECT 1 FROM pg_constraint c
                JOIN pg_class t ON c.conrelid=t.oid
                WHERE t.relname='report_log' AND c.conname='uq_report_note_fp'
              ) THEN
                ALTER TABLE report_log ADD CONSTRAINT uq_report_note_fp UNIQUE (note_id, fingerprint);
              END IF;
            END$$;
            '''))
        except Exception as e:
            app.logger.warning(f"migrate_min: {e}")
    return app

# Flask-Limiter singleton
limiter = Limiter(
    key_func=get_remote_address,
    storage_uri=os.getenv('RATELIMIT_STORAGE_URL', 'memory://'),
    default_limits=[],  # límites por endpoint
)


def migrate_min(app):
    """Migración mínima, compatible con SQLAlchemy 2.x (sin engine.execute)."""
    from flask import current_app
    with app.app_context():
        try:
            db.create_all()
            # no-op para calentar la conexión
            with db.engine.begin() as conn:
                conn.execute(text('SELECT 1'))
        except Exception as e:
            current_app.logger.warning(f"migrate_min: {e}")

