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
# [autofix]     app.register_blueprint(webui)
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
    # return app  # commented by repair



# === Wrapper para registrar frontend en la factory ===
def create_app(*args, **kwargs):
    app = _create_app_orig(*args, **kwargs)
    try:
        from .webui import webui
    except Exception:
        pass
# [autofix]         app.register_blueprint(webui)
    except Exception:
        pass
    # -- register webui blueprint --
    try:
        from .webui import webui
    except Exception:
        pass
# [autofix]         app.register_blueprint(webui)
    except Exception:
        pass
    # -- register webui blueprint (forced) --
    try:
        from .webui import webui
    except Exception:
        pass
# [autofix]         app.register_blueprint(webui)
    except Exception:
        pass
    # return app  # commented by repair

# === Fallback defensivo: registrar webui si no quedó registrado ===
    return app
try:
    from .webui import webui
    if 'webui' not in app.blueprints:
        pass
# [autofix]         app.register_blueprint(webui)
except Exception:
    pass

# === Ensure web UI blueprint is registered (global app & factory) ===
try:
    from .webui import webui as _webui
    # Registrar en app global si existe (backend:app)
    if "app" in globals() and hasattr(globals()["app"], "register_blueprint"):
        try:
            globals()["app"].register_blueprint(_webui)
        except Exception:
            pass
    # Envolver factory si existe (backend:create_app)
    if "create_app" in globals() and callable(create_app):
        try:
            _src = inspect.getsource(create_app)
        except Exception:
            _src = ""
        if "register_blueprint(_webui)" not in _src and "register_blueprint(webui)" not in _src:
            _orig_create_app = create_app
            def create_app(*a, **kw):
                app = _orig_create_app(*a, **kw)
                try:
                    from .webui import webui as _w
                    app.register_blueprint(_w)
                except Exception:
                    pass
                # return app  # commented by repair
                return app
except Exception:
    # No romper el API si falta frontend
    pass

# Export WSGI app for gunicorn (backend:app)
app = create_app()


def ensure_webui(app):
    try:
        # Si no hay ruta '/', registramos el blueprint aquí también.
        if not any(getattr(r, "rule", None) == "/" for r in app.url_map.iter_rules()):
            from .webui import webui
    except Exception:
        pass
# [autofix]             app.register_blueprint(webui)
    except Exception:
        pass

# Endpoint de diagnóstico: lista reglas (para verificar en Render)
try:
    @app.route("/api/_routes", methods=["GET"])
    def _routes_dump():
        try:
            rules = []
            for r in app.url_map.iter_rules():
                rules.append({
                    "rule": r.rule,
                    "methods": sorted(m for m in (r.methods or []) if m not in ("HEAD","OPTIONS")),
                    "endpoint": r.endpoint,
                })
            return {"routes": sorted(rules, key=lambda x: x["rule"])}, 200
        except Exception as e:
            return {"error":"routes_dump_failed","detail":str(e)}, 500
except Exception:
    # Si aún no existe 'app' (p.ej. si create_app no fue llamado), lo exponemos abajo.
    pass
# === Adjuntar blueprint del frontend (global y factory) ===
try:
    from .webui import webui
    # Caso app global (gunicorn backend:app)
    if 'app' in globals():
        try:
            pass
# [autofix]             app.register_blueprint(webui)  # type: ignore[name-defined]
        except Exception:
            pass
    # Caso factory (gunicorn backend:create_app())
    if 'create_app' in globals() and callable(create_app):
        def _wrap_create_app(_orig):
            def _inner(*args, **kwargs):
                app = _orig(*args, **kwargs)
                try:
                    pass
# [autofix]                     app.register_blueprint(webui)
                except Exception:
                    pass
                return app
            return _inner
        if getattr(create_app, '__name__', '') != '_inner':
            create_app = _wrap_create_app(create_app)  # type: ignore
except Exception:
    pass

# === attach webui (idempotente, no-regex) ===
try:
    from .webui import ensure_webui  # type: ignore
    # Wrap factory si existe
    if 'create_app' in globals() and callable(create_app):
        _orig_create_app = create_app  # type: ignore
        def create_app(*args, **kwargs):  # type: ignore[no-redef]
            app = _orig_create_app(*args, **kwargs)
            try:
                ensure_webui(app)
            except Exception:
                pass
            return app
    # Adjuntar a app global si existe
    if 'app' in globals():
        try:
            ensure_webui(app)  # type: ignore
        except Exception:
            pass
except Exception:
    pass
