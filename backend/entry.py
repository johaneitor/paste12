# Punto de entrada WSGI estable para Render: backend.entry:app
from pathlib import Path
try:
    # Preferimos factory si existe
    from backend import create_app as _factory  # type: ignore
except Exception:
    _factory = None

app = None
if _factory:
    try:
        app = _factory()
    except Exception:
        app = None

if app is None:
    # Fallback a 'app' global si la app no es factory o si falló
    from backend import app as _app  # type: ignore
    app = _app

# Intentar registrar el blueprint webui
try:
    from backend.webui import webui  # type: ignore
    app.register_blueprint(webui)    # type: ignore[attr-defined]
except Exception:
    # Fallback duro: definir rutas estáticas inline
    from flask import send_from_directory
    PKG_DIR = Path(__file__).resolve().parent
    candidates = [
        PKG_DIR / "frontend",
        PKG_DIR.parent / "frontend",
        Path.cwd() / "frontend",
    ]
    for c in candidates:
        if c.exists():
            FRONT_DIR = c
            break
    else:
        FRONT_DIR = candidates[0]

    @app.get("/")  # type: ignore[misc]
    def _index():
        return send_from_directory(FRONT_DIR, "index.html")

    @app.get("/js/<path:fname>")  # type: ignore[misc]
    def _js(fname):
        return send_from_directory(FRONT_DIR / "js", fname)

    @app.get("/css/<path:fname>")  # type: ignore[misc]
    def _css(fname):
        return send_from_directory(FRONT_DIR / "css", fname)

    @app.get("/robots.txt")  # type: ignore[misc]
    def _robots():
        p = FRONT_DIR / "robots.txt"
        return (send_from_directory(FRONT_DIR, "robots.txt") if p.exists() else ("", 204))

    @app.get("/favicon.ico")  # type: ignore[misc]
    def _favicon():
        p = FRONT_DIR / "favicon.ico"
        return (send_from_directory(FRONT_DIR, "favicon.ico") if p.exists() else ("", 204))
