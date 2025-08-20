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

    # -- Registrar rutas frontend (idempotente) --

    def _ensure_front_routes(app):

        try:

            existing_rules = {r.rule for r in app.url_map.iter_rules()}

            existing_eps   = set(app.view_functions.keys())

        except Exception:

            existing_rules, existing_eps = set(), set()

        import os

        from flask import abort

        static_folder = app.static_folder

        # /favicon.ico

        if '/favicon.ico' not in existing_rules:

            app.add_url_rule('/favicon.ico', endpoint='favicon_svg',

                             view_func=lambda: send_from_directory(static_folder, 'favicon.svg', mimetype='image/svg+xml'))

        # /ads.txt

        if '/ads.txt' not in existing_rules:

            app.add_url_rule('/ads.txt', endpoint='ads_txt_file',

                             view_func=lambda: send_from_directory(static_folder, 'ads.txt', mimetype='text/plain'))

        # /

        if '/' not in existing_rules:

            app.add_url_rule('/', endpoint='root_index',

                             view_func=lambda: send_from_directory(static_folder, 'index.html'))

        # Fallback SPA: /<path:path> (evita /api/*)

        if 'static_any' not in existing_eps:

            def static_any(path):

                if path.startswith('api/'):

                    return abort(404)

                full = os.path.join(static_folder, path)

                if os.path.isfile(full):

                    return send_from_directory(static_folder, path)

                return send_from_directory(static_folder, 'index.html')

            app.add_url_rule('/<path:path>', endpoint='static_any', view_func=static_any)

    _ensure_front_routes(app)


    # -- Registrar rutas del frontend (idempotente) --


    return app
