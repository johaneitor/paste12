from backend.routes import api
# -*- coding: utf-8 -*-
import os
import re
import datetime as dt
from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy import text as sql_text

# == paste12: normalize DATABASE_URL ==
def _normalize_db_url(url: str) -> str:
    if not url: return url
    # postgres:// -> postgresql+psycopg2://
    if url.startswith("postgres://"):
        return "postgresql+psycopg2://" + url[len("postgres://"):]
    return url

try:
    _env_url = os.environ.get("DATABASE_URL", "") or os.environ.get("DB_URL", "")
    _norm_url = _normalize_db_url(_env_url)
    if _norm_url and _norm_url != _env_url:
        os.environ["DATABASE_URL"] = _norm_url
except Exception:
    pass
# == end normalize ==



# --- helpers ---------------------------------------------------------------
def normalize_db_url(u: str) -> str:
    if not u:
        return "sqlite:///paste12.db"
    # Render free-tier suele entregar postgres://, SQLAlchemy quiere postgresql+psycopg2://
    if u.startswith("postgres://"):
        u = "postgresql+psycopg2://" + u.split("://", 1)[1]
    return u

# --- app -------------------------------------------------------------------
app = Flask(__name__, static_folder="../frontend", static_url_path="")
CORS(app, resources={r"/api/*": {"origins": "*"}}, supports_credentials=False)

db_uri = normalize_db_url(os.getenv("DATABASE_URL", ""))

engine_opts = {
    "pool_pre_ping": True,                          # evita conexiones rotas (SSL bad record mac / EOF)
    "pool_recycle": int(os.getenv("SQL_POOL_RECYCLE", "300")),
    "pool_size": int(os.getenv("SQL_POOL_SIZE", "5")),
    "max_overflow": int(os.getenv("SQL_MAX_OVERFLOW", "5")),
}

app.config["SQLALCHEMY_DATABASE_URI"] = db_uri
app.config.setdefault("SQLALCHEMY_ENGINE_OPTIONS", {
    "pool_pre_ping": True,
    "pool_recycle": 180,
    "pool_timeout": 15,
    "pool_size": 5,
    "max_overflow": 10,
})

app.config.setdefault("SQLALCHEMY_ENGINE_OPTIONS", {
    "pool_pre_ping": True,
    "pool_recycle": 180,
    "pool_timeout": 15,
    "pool_size": 5,
    "max_overflow": 10,
})

app.config.setdefault("SQLALCHEMY_ENGINE_OPTIONS", {
    "pool_pre_ping": True,
    "pool_recycle": 180,
    "pool_timeout": 15,
    "pool_size": 5,
    "max_overflow": 10,
})

app.config.setdefault("SQLALCHEMY_ENGINE_OPTIONS", {
    "pool_pre_ping": True,
    "pool_recycle": 180,
    "pool_timeout": 15,
    "pool_size": 5,
    "max_overflow": 10,
})

app.config.setdefault("SQLALCHEMY_ENGINE_OPTIONS", {
    "pool_pre_ping": True,
    "pool_recycle": 180,
    "pool_timeout": 15,
    "pool_size": 5,
    "max_overflow": 10,
})

app.config.setdefault("SQLALCHEMY_ENGINE_OPTIONS", {
    "pool_pre_ping": True,
    "pool_recycle": 180,
    "pool_timeout": 15,
    "pool_size": 5,
    "max_overflow": 10,
})

app.config.setdefault("SQLALCHEMY_ENGINE_OPTIONS", {
    "pool_pre_ping": True,
    "pool_recycle": 180,
    "pool_timeout": 15,
    "pool_size": 5,
    "max_overflow": 10,
})

app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

db = SQLAlchemy(app, engine_options=engine_opts)

# --- models ----------------------------------------------------------------
class Note(db.Model):
    __tablename__ = "notes"
    id = db.Column(db.Integer, primary_key=True)
    text = db.Column(db.Text, nullable=False)
    timestamp = db.Column(db.DateTime, nullable=False, index=True, default=dt.datetime.utcnow)
    expires_at = db.Column(db.DateTime, index=True)
    likes = db.Column(db.Integer, nullable=False, default=0)
    views = db.Column(db.Integer, nullable=False, default=0)
    reports = db.Column(db.Integer, nullable=False, default=0)
    author_fp = db.Column(db.String(64), index=True)

# --- guards: pre-ping y cleanup -------------------------------------------
@app.before_request
def _pre_ping():
    # Toca la conexión; si está muerta el pool_pre_ping la reemplaza.
    try:
        db.session.execute(sql_text("SELECT 1"))
    except Exception:
        # En caso de error, reinicia la sesión para el request actual.
        db.session.remove()

@app.teardown_appcontext
def _shutdown_session(exception=None):
    db.session.remove()

# --- importa rutas (usa app/db/Note ya definidos) --------------------------
try:
    from . import routes  # noqa: F401
except Exception:
    # No rompas el import si aún no existen/compilan las rutas en tiempo de build.
    pass

# --- exports WSGI ----------------------------------------------------------
application = app
__all__ = ["app", "db", "Note", "application"]


from flask import Flask
from flask_sqlalchemy import SQLAlchemy
db = SQLAlchemy()

def create_app():
    app = Flask(__name__)
    attach_pooling(app, db)
    app.register_blueprint(api_bp)
    CORS(app, resources={r"/*": {"origins": "*"}})
    app.config['SQLALCHEMY_DATABASE_URI'] = SQLALCHEMY_DATABASE_URI
    app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
    db.init_app(app)
    try:
        from backend import routes as _routes  # registra vistas si existen
        if hasattr(_routes,'init_app'): _routes.init_app(app)
    except Exception:
        pass
    @app.get('/api/health')
    def _health(): return {'ok': True, 'api': True, 'ver':'fallback'}
    return app

from flask import Flask, request, jsonify
from flask_cors import CORS
from datetime import timedelta

# == soft DB guard / helpers ==
try:
    from sqlalchemy import text
except Exception:
    text = None

def _db_ping_ok(app, db):
    if not text:  # sin SQLAlchemy text, salir "ok"
        return True
    try:
        with db.engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return True
    except Exception as e:
        try:
            app.logger.warning("db ping fail: %s", e)
        except Exception:
            pass
        return False

def _install_soft_db_guard(app, db):
    @app.before_request
    def _only_guard_writes():
        # dejar pasar health y todo GET/HEAD/OPTIONS
        if request.method in ("GET","HEAD","OPTIONS"):
            return None
        if not request.path.startswith("/api/"):
            return None
        if not _db_ping_ok(app, db):
            return ("Service temporarily unavailable (db)", 503, {"Content-Type":"text/plain"})
        return None


app.register_blueprint(api)

@app.route('/api/health')
def health():
    return {"ok": True, "api": True, "ver": "wsgi-lazy-v2"}
