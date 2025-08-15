import os
from datetime import datetime, timezone, timedelta
from flask import Flask, send_from_directory
from flask_sqlalchemy import SQLAlchemy
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from flask_cors import CORS
from apscheduler.schedulers.background import BackgroundScheduler

db = SQLAlchemy()

def create_app():
    # Rutas base
    base_dir   = os.path.abspath(os.path.dirname(__file__))
    static_dir = os.path.join(base_dir, "..", "frontend")

    app = Flask(__name__, static_folder=static_dir, static_url_path="")

    # Config
    os.makedirs(app.instance_path, exist_ok=True)
    app.config.from_mapping(
        SECRET_KEY=os.getenv("SECRET_KEY", "dev-secret"),
        SQLALCHEMY_DATABASE_URI=os.getenv(
            "DATABASE_URL",
            "sqlite:///" + os.path.join(app.instance_path, "production.db")
        ),
        SQLALCHEMY_TRACK_MODIFICATIONS=False,
        RATELIMIT_STORAGE_URL=os.getenv("RATELIMIT_STORAGE_URL", "memory://"),
        JSON_SORT_KEYS=False,
    )

    # Extensiones
    db.init_app(app)
    Limiter(key_func=get_remote_address, app=app, default_limits=["60 per minute"])
    CORS(app)

    # Blueprints
    from . import routes
    app.register_blueprint(routes.bp)

    # Frontend
    @app.route("/")
    def index():
        return send_from_directory(app.static_folder, "index.html")

    # Scheduler opcional (deshabilitable en local)
    if not os.getenv("DISABLE_SCHEDULER"):
        try:
            from .tasks import purge_expired
            sch = BackgroundScheduler(timezone=timezone.utc)
            sch.add_job(lambda: purge_expired(app), "interval", minutes=30)
            sch.start()
        except Exception as e:
            app.logger.warning(f"Scheduler no iniciado: {e}")

    # DB
    with app.app_context():
        db.create_all()

    return app
