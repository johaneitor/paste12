import os
from pathlib import Path
from flask import Flask, send_from_directory
from flask_sqlalchemy import SQLAlchemy
from flask_cors import CORS
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

# SQLAlchemy singleton del paquete (otros módulos hacen "from . import db")
db = SQLAlchemy()

def create_app():
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

    return app
