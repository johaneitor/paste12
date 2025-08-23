# wsgi.py — robusto para gunicorn wsgi:app
# Intenta varias formas de obtener la Flask app y registra el webui si existe.
from flask import Flask, jsonify
app = None

# 1) Preferir backend.entry:app si existe
try:
    from backend.entry import app as _app  # type: ignore
    app = _app
except Exception:
    pass

# 2) backend:app (objeto global)
if app is None:
    try:
        from backend import app as _app  # type: ignore
        app = _app
    except Exception:
        pass

# 3) backend:create_app() (factory)
if app is None:
    try:
        from backend import create_app as _factory  # type: ignore
        app = _factory()
    except Exception:
        pass

# 4) Último recurso: app mínima para no romper el deploy
if app is None:
    app = Flask(__name__)
    @app.get("/api/health")
    def _health():
        return jsonify({"ok": True, "note": "fallback wsgi"}), 200

# 5) Adjuntar frontend (idempotente)
try:
    from backend.webui import ensure_webui  # type: ignore
    ensure_webui(app)  # type: ignore
except Exception:
    # No romper si no está el webui
    pass

# --- Force-load API routes so endpoints exist in production ---
try:
    import backend.routes  # noqa: F401
except Exception:
    # Do not crash the app if routes import fails; API health must remain up
    pass

