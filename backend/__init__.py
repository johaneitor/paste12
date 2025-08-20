from __future__ import annotations
import os
from datetime import timezone
from flask import Flask, send_from_directory
from flask_sqlalchemy import SQLAlchemy
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from sqlalchemy import text
try:
    from flask_compress import Compress
except Exception:
    Compress = None
try:
    from werkzeug.middleware.proxy_fix import ProxyFix
except Exception:
    ProxyFix = None

# --- Singletons globales ---
db = SQLAlchemy()
limiter = Limiter(key_func=get_remote_address, default_limits=[])

def _register_frontend(app: Flask) -> None:
    """Rutas estáticas idempotentes para frontend SPA."""
    static_folder = app.static_folder

    # Evitar duplicados
    existing_rules = {r.rule for r in app.url_map.iter_rules()}
    if '/favicon.ico' not in existing_rules:
        app.add_url_rule('/favicon.ico', 'static_favicon',
                         lambda: send_from_directory(static_folder, 'favicon.svg', mimetype='image/svg+xml'))
    if '/ads.txt' not in existing_rules:
        app.add_url_rule('/ads.txt', 'static_ads',
                         lambda: send_from_directory(static_folder, 'ads.txt', mimetype='text/plain'))
    if '/' not in existing_rules:
        app.add_url_rule('/', 'static_root',
                         lambda: send_from_directory(static_folder, 'index.html'))

    # Fallback SPA, bloquea /api/*
    from flask import abort
    import os as _os
    def static_any(path: str):
        if path.startswith('api/'):
            return abort(404)
        full = _os.path.join(static_folder, path)
        if _os.path.isfile(full):
            return send_from_directory(static_folder, path)
        return send_from_directory(static_folder, 'index.html')
    if 'static_any' not in app.view_functions:
        app.add_url_rule('/<path:path>', 'static_any', static_any)

def create_app():
    app = Flask(__name__, static_folder='frontend', static_url_path='')

    # Proxy headers (Render)
    if ProxyFix:
        app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1)

    # --- Config DB ---
    uri = os.getenv('DATABASE_URL', 'sqlite:///instance/production.db')
    # Compat render postgres:// -> postgresql+psycopg2://
    if uri.startswith('postgres://'):
        uri = uri.replace('postgres://', 'postgresql+psycopg2://', 1)
    app.config['SQLALCHEMY_DATABASE_URI'] = uri
    app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
    # Conexiones más resilientes (Render)
    app.config['SQLALCHEMY_ENGINE_OPTIONS'] = {
        'pool_pre_ping': True,
        'pool_recycle': 280,
    }

    # Init extensiones
    db.init_app(app)
    limiter.init_app(app)
    if Compress:
        try: Compress(app)
        except Exception: pass

    # Registrar frontend
    _register_frontend(app)

    # Registrar API
    try:
        from .routes import bp as api_bp
        # Si routes.py usa @bp = Blueprint('api', __name__), ponemos prefijo aquí:
        app.register_blueprint(api_bp, url_prefix='/api')
    except Exception as e:
        app.logger.warning(f'No se pudo registrar blueprint API: {e}')

    # Migración mínima + ping DB
    with app.app_context():
        try:
            db.create_all()
            with db.engine.begin() as conn:
                conn.execute(text('SELECT 1'))
        except Exception as e:
            app.logger.warning(f'migrate_min/db ping: {e}')

    # Scheduler opcional (purga de expiradas)
    if not os.getenv('DISABLE_SCHEDULER'):
        try:
            from apscheduler.schedulers.background import BackgroundScheduler
            from .tasks import purge_expired
            sch = BackgroundScheduler(timezone=timezone.utc)
            sch.add_job(lambda: purge_expired(app), 'interval', minutes=30)
            sch.start()
        except Exception as e:
            app.logger.warning(f'scheduler deshabilitado: {e}')

    return app
