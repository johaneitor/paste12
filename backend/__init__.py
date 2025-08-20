# backend/__init__.py — clean reset: DB + Limiter + API + static frontend
import os
from datetime import timezone
from flask import Flask, send_from_directory, abort
from flask_sqlalchemy import SQLAlchemy
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from sqlalchemy import text

# Extensiones como singletons a nivel módulo (para 'from backend import db, limiter')
db = SQLAlchemy()
limiter = Limiter(key_func=get_remote_address, default_limits=[])

def _abs(path: str) -> str:
    return os.path.abspath(os.path.join(os.path.dirname(__file__), path))

def _build_database_uri() -> str:
    url = os.getenv("DATABASE_URL")
    if not url:
        os.makedirs(_abs("../instance"), exist_ok=True)
        return "sqlite:///" + _abs("../instance/production.db")
    if url.startswith(("postgres://", "postgresql://")) and "sslmode=" not in url:
        url += ("&" if "?" in url else "?") + "sslmode=require"
    return url

def create_app():
    import os
    from sqlalchemy import text

    app = Flask(__name__, static_folder=os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "frontend")), static_url_path="")

    # --- Config básica ---
    uri = os.getenv("DATABASE_URL") or os.getenv("SQLALCHEMY_DATABASE_URI")
    if not uri:
        # fallback a SQLite local
        base = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "instance"))
        os.makedirs(base, exist_ok=True)
        uri = f"sqlite:///{os.path.join(base, "production.db")}"
    app.config["SQLALCHEMY_DATABASE_URI"] = uri
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

    # --- Inicializar extensiones (una vez) ---
    try:
        db.init_app(app)
    except Exception:
        # ya estaba inicializado; ignorar
        pass
    try:
        limiter.init_app(app)
    except Exception:
        pass

    # --- Registrar blueprint /api (idempotente) ---
    try:
        from . import routes as _routes
        if "api" not in app.blueprints:
            app.register_blueprint(_routes.bp, url_prefix="/api")
    except Exception as e:
        app.logger.error(f"No se pudo registrar blueprint API: {e}")

    # --- Rutas estáticas/SPA (idempotentes) ---
    try:
        rules = {r.rule for r in app.url_map.iter_rules()}
        if "/favicon.ico" not in rules:
            app.add_url_rule(
                "/favicon.ico",
                endpoint="static_favicon",
                view_func=lambda: send_from_directory(app.static_folder, "favicon.svg", mimetype="image/svg+xml"),
            )
        if "/ads.txt" not in rules:
            app.add_url_rule(
                "/ads.txt",
                endpoint="static_ads",
                view_func=lambda: send_from_directory(app.static_folder, "ads.txt", mimetype="text/plain"),
            )
        if "/" not in rules:
            app.add_url_rule(
                "/",
                endpoint="static_root",
                view_func=lambda: send_from_directory(app.static_folder, "index.html"),
            )
        if "static_any" not in app.view_functions:
            from flask import abort
            def static_any(path):
                if path.startswith("api/"):
                    return abort(404)
                full = os.path.join(app.static_folder, path)
                if os.path.isfile(full):
                    return send_from_directory(app.static_folder, path)
                return send_from_directory(app.static_folder, "index.html")
            app.add_url_rule("/<path:path>", endpoint="static_any", view_func=static_any)
    except Exception as e:
        app.logger.warning(f"Rutas estáticas: {e}")

    # --- Índices útiles (no falla si ya existen) ---
    try:
        with app.app_context():
            with db.engine.begin() as conn:
                conn.execute(text("CREATE INDEX IF NOT EXISTS ix_note_expires_at ON note (expires_at)"))
                conn.execute(text("CREATE INDEX IF NOT EXISTS ix_note_exp_ts ON note (expires_at, timestamp)"))
    except Exception as e:
        app.logger.warning(f"Índices: {e}")

    # --- Cap de notas al arrancar (si está implementado) ---
    try:
        from .tasks import enforce_cap_on_boot
        enforce_cap_on_boot(app)
    except Exception as e:
        app.logger.warning(f"enforce_cap_on_boot: {e}")

    return app
