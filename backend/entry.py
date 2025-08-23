# backend.entry: app
from pathlib import Path

# Preferimos factory si existe; si no, app global
app = None
try:
    from backend import create_app as _factory  # type: ignore
except Exception:
    _factory = None

if _factory:
    try:
        app = _factory()
    except Exception:
        app = None

if app is None:
    from backend import app as _app  # type: ignore
    app = _app

# Adjuntar frontend (blueprint) si existe; sino fallback estático
try:
    from backend.webui import ensure_webui  # type: ignore
    ensure_webui(app)  # type: ignore
except Exception:
    try:
        from flask import send_from_directory
        PKG_DIR = Path(__file__).resolve().parent
        candidates = [PKG_DIR/"frontend", PKG_DIR.parent/"frontend", Path.cwd()/"frontend"]
        FRONT_DIR = next((c for c in candidates if c.exists()), candidates[0])

        @app.get("/")            # type: ignore
        def _index(): return send_from_directory(FRONT_DIR, "index.html")
        @app.get("/js/<path:f>") # type: ignore
        def _js(f): return send_from_directory(FRONT_DIR/"js", f)
        @app.get("/css/<path:f>")# type: ignore
        def _css(f): return send_from_directory(FRONT_DIR/"css", f)
        @app.get("/robots.txt")  # type: ignore
        def _robots():
            p = FRONT_DIR/"robots.txt"
            return (send_from_directory(FRONT_DIR, "robots.txt") if p.exists() else ("", 204))
        @app.get("/favicon.ico") # type: ignore
        def _ico():
            p = FRONT_DIR/"favicon.ico"
            return (send_from_directory(FRONT_DIR, "favicon.ico") if p.exists() else ("", 204))
    except Exception:
        pass
