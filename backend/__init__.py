import psycopg2
import os
from flask import request, make_response
from flask import send_from_directory, abort
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

# === Normalize DATABASE_URL (protocol + SSL) ===
import urllib.parse as _u
_dburl = app.config.get('SQLALCHEMY_DATABASE_URI') or os.environ.get('DATABASE_URL','')
if _dburl.startswith('postgres://'):
    _dburl = 'postgresql+psycopg2://' + _dburl[len('postgres://'):]
elif _dburl.startswith('postgresql://'):
    _dburl = 'postgresql+psycopg2://' + _dburl[len('postgresql://'):]
# sslmode=require si no está
if 'sslmode=' not in _dburl:
    sep = '&' if '?' in _dburl else '?'
    _dburl = _dburl + f"{sep}sslmode=require"
app.config['SQLALCHEMY_DATABASE_URI'] = _dburl
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


# --- pastel root (idempotente): sirve backend/static/index.html en "/" ---
def _serve_pastel_root():
    try:
        here = os.path.dirname(__file__)
        p = os.path.join(here, "static", "index.html")
        with open(p, "rb") as f:
            data = f.read()
    except Exception:
        return None  # dejar que siga el ruteo normal
    resp = make_response(data, 200)
    resp.headers["Content-Type"] = "text/html; charset=utf-8"
    resp.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    resp.headers["X-Index-Source"] = "app-base"
    return resp

try:
    # 'app' debe existir en este módulo (Flask app)
    app
    if not getattr(app, "_pastel_root_installed", False):
        @app.before_request
        def _pastel_root_intercept():
            # intercepta solo GET/HEAD de "/" o "/index.html"
            m = (request.method or "GET").upper()
            if request.path in ("/", "/index.html") and m in ("GET", "HEAD"):
                resp = _serve_pastel_root()
                if resp is not None and m == "HEAD":
                    # sin cuerpo en HEAD
                    resp.set_data(b"")
                return resp  # corta el ruteo
        app._pastel_root_installed = True
except NameError:
    # si no hay 'app', no hacemos nada (ambiente no esperado)
    pass

# === Paste12 OperationalError handler ===
try:
    from sqlalchemy.exc import OperationalError
    from flask import jsonify
    try:
        from backend.models import db as __p12_db
    except Exception:
        try:
            from models import db as __p12_db
        except Exception:
            __p12_db = None
    @app.errorhandler(OperationalError)
    def __p12_db_operational_error(e):
        try:
            if __p12_db is not None:
                __p12_db.session.remove()
        except Exception:
            pass
        return jsonify(ok=False, error="db_unavailable", kind="OperationalError"), 503
except Exception:
    pass
# === /Paste12 OperationalError handler ===


@app.errorhandler(psycopg2.OperationalError)
def _psycopg_operational(e):
    from flask import jsonify
    try: db.session.remove()
    except Exception: pass
    return jsonify(ok=False,error='db_unavailable',detail='psycopg2.OperationalError'),503

# --- DB error handlers (coherentes) ---
from sqlalchemy.exc import OperationalError, DBAPIError
from flask import jsonify

def _db_fail(e):
    # No revela detalles
    return jsonify({"ok": False, "db": "unavailable"}), 503

@app.errorhandler(OperationalError)
def _operr(e): return _db_fail(e)

@app.errorhandler(DBAPIError)
def _dberr(e): return _db_fail(e)
