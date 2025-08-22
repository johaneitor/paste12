from __future__ import annotations
import os, re, logging, threading, time, json
from datetime import datetime, timedelta, date
from flask import Flask, g, request
from flask_sqlalchemy import SQLAlchemy

# Extensiones
db = SQLAlchemy()

# Limiter opcional (no revienta si no está instalado)
try:
    from flask_limiter import Limiter
    from flask_limiter.util import get_remote_address
    class _LimiterWrapper:
        def __init__(self): self._limiter = None
        def init_app(self, app):
            def key_func():
                uid = request.cookies.get('uid')
                return uid or get_remote_address()
            self._limiter = Limiter(key_func=key_func, default_limits=[])
            self._limiter.init_app(app)
        def limit(self, *a, **k):
            if self._limiter is None:
                def deco(f): return f
                return deco
            return self._limiter.limit(*a, **k)
    limiter = _LimiterWrapper()
except Exception:
    class _NoopLimiter:
        def init_app(self, app): pass
        def limit(self, *a, **k):
            def deco(f): return f
            return deco
    limiter = _NoopLimiter()

def _db_uri() -> str:
    uri = os.getenv("DATABASE_URL")
    if uri:
        uri = re.sub(r"^postgres://", "postgresql+psycopg://", uri)
        if uri.startswith("postgresql://") and "+psycopg://" not in uri:
            uri = uri.replace("postgresql://","postgresql+psycopg://",1)
        return uri
    import pathlib
    return f"sqlite:///{pathlib.Path('data/app.db').resolve()}"

def _cleanup_once(app: Flask):
    """Borra expiradas y logs viejos (seguro para SQLite/Postgres)."""
    from .models import Note, LikeLog, ViewLog, ReportLog  # import diferido
    with app.app_context():
        now = datetime.utcnow()
        try:
            db.session.query(Note).filter(
                Note.expires_at.isnot(None),
                Note.expires_at < now
            ).delete(synchronize_session=False)
        except Exception as e:
            app.logger.warning(f"cleanup notes: {e}")
        try:
            db.session.query(ViewLog).filter(
                ViewLog.view_date < (now.date() - timedelta(days=30))
            ).delete(synchronize_session=False)
            db.session.query(LikeLog).filter(
                LikeLog.created_at < (now - timedelta(days=90))
            ).delete(synchronize_session=False)
            db.session.query(ReportLog).filter(
                ReportLog.created_at < (now - timedelta(days=180))
            ).delete(synchronize_session=False)
        except Exception as e:
            app.logger.warning(f"cleanup logs: {e}")
        db.session.commit()

def _maybe_schedule_cleanup(app: Flask):
    if os.getenv("ENABLE_CLEANUP_LOOP","0") != "1":
        return
    interval = int(os.getenv("CLEANUP_EVERY_SECONDS","21600"))  # 6h
    def loop():
        while True:
            try: _cleanup_once(app)
            except Exception as e: app.logger.warning(f"cleanup loop: {e}")
            time.sleep(interval)
    t = threading.Thread(target=loop, daemon=True)
    t.start()

def _create_app_orig() -> Flask:
    app = Flask(__name__)
# Registrar blueprint del frontend
try:
    from .webui import webui
    app.register_blueprint(webui)
except Exception:
    pass

    app.config["SQLALCHEMY_DATABASE_URI"] = _db_uri()
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {"pool_pre_ping": True, "pool_recycle": 280}

    db.init_app(app)
    # Sentry opcional
    try:
        import sentry_sdk
        from sentry_sdk.integrations.flask import FlaskIntegration
        from sentry_sdk.integrations.sqlalchemy import SqlalchemyIntegration
        dsn = os.getenv('SENTRY_DSN')
        if dsn:
            sentry_sdk.init(dsn=dsn, integrations=[FlaskIntegration(), SqlalchemyIntegration()], traces_sample_rate=float(os.getenv('SENTRY_TRACES','0')))
    except Exception as _e:
        app.logger.warning(f'Sentry init: {_e}')
    try: limiter.init_app(app)
    except Exception as e: app.logger.warning(f"Limiter init: {e}")

    # logging simple (JSON) si LOG_JSON=1
    if os.getenv("LOG_JSON","0") == "1":
        @app.before_request
        def _t0(): g._t0 = time.perf_counter()
        @app.after_request
        def _log(resp):
            try:
                dt = int((time.perf_counter() - getattr(g,"_t0",time.perf_counter()))*1000)
                app.logger.info(json.dumps({"m":request.method,"p":request.path,"s":resp.status_code,"ms":dt}))
            except Exception: pass
            return resp

    from .routes import api as api_blueprint
    app.register_blueprint(api_blueprint)

    with app.app_context():
        db.create_all()

    _maybe_schedule_cleanup(app)
    return app



# === Wrapper para registrar frontend en la factory ===
def create_app(*args, **kwargs):
    app = _create_app_orig(*args, **kwargs)
    try:
        from .webui import webui
        app.register_blueprint(webui)
    except Exception:
        pass
    return app
