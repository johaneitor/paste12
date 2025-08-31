import os
from flask import send_from_directory, abort
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

    try: _setup_root(app)
    except Exception as _e: pass
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


# === paste12: rutas estáticas mínimas para servir la web ===
def _setup_root(app):
    static_dir = app.static_folder or os.path.join(os.path.dirname(__file__), "static")

    # / → index.html
    def _index():
        path = os.path.join(static_dir, "index.html")
        if os.path.isfile(path):
            return send_from_directory(static_dir, "index.html")
        abort(404)
    app.add_url_rule("/", endpoint="root_index", view_func=_index)

    # /privacy y /terms si existen
    def _serve_privacy():
        p = os.path.join(static_dir, "privacy.html")
        if os.path.isfile(p): return send_from_directory(static_dir, "privacy.html")
        abort(404)
    app.add_url_rule("/privacy", endpoint="serve_privacy", view_func=_serve_privacy)

    def _serve_terms():
        p = os.path.join(static_dir, "terms.html")
        if os.path.isfile(p): return send_from_directory(static_dir, "terms.html")
        abort(404)
    app.add_url_rule("/terms", endpoint="serve_terms", view_func=_serve_terms)

    # assets comunes (coinciden con tu index)
    def _serve_css(path):  return send_from_directory(os.path.join(static_dir, "css"), path)
    def _serve_js(path):   return send_from_directory(os.path.join(static_dir, "js"),  path)
    def _serve_front_js(p):return send_from_directory(os.path.join(static_dir, "frontend/js"), p)

    app.add_url_rule("/css/<path:path>", endpoint="css_files", view_func=_serve_css)
    app.add_url_rule("/js/<path:path>",  endpoint="js_files",  view_func=_serve_js)
    app.add_url_rule("/frontend/js/<path:path>", endpoint="front_js_files", view_func=_serve_front_js)

    # raíz de estáticos directos
    def _serve_root_file(fname):
        return send_from_directory(static_dir, fname)
    for fname, ep in (("favicon.svg","favicon_svg"), ("favicon.ico","favicon_ico"),
                      ("robots.txt","robots_txt"), ("ads.txt","ads_txt")):
        app.add_url_rule(f"/{fname}", endpoint=ep, view_func=(lambda f=fname: _serve_root_file(f)))
