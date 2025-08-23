# WSGI entrypoint robusto para Render: backend.entry:app
from pathlib import Path
from flask import send_from_directory, jsonify

def _make_app():
    # Preferimos factory si existe
    try:
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
        # Fallback a 'app' global
        from backend import app as _app  # type: ignore
        app = _app

    return app

app = _make_app()

# --- Diagnóstico de rutas
@app.get("/api/_routes")
def _routes():
    info = []
    for r in app.url_map.iter_rules():
        info.append({
            "rule": str(r),
            "methods": sorted(m for m in r.methods if m not in ("HEAD", "OPTIONS")),
            "endpoint": r.endpoint,
        })
    return jsonify({"routes": sorted(info, key=lambda x: x["rule"])}), 200

# --- Frontend: intentar blueprint; si falla, rutas inline
try:
    from backend.webui import webui  # type: ignore
    if "webui.index" not in app.view_functions:
        app.register_blueprint(webui)  # type: ignore[attr-defined]
except Exception:
    PKG = Path(__file__).resolve().parent
    candidates = [PKG / "frontend", PKG.parent / "frontend", Path.cwd() / "frontend"]
    FRONT_DIR = next((c for c in candidates if c.exists()), candidates[0])

    @app.get("/")
    def _index():
        return send_from_directory(FRONT_DIR, "index.html")

    @app.get("/js/<path:fname>")
    def _js(fname):
        return send_from_directory(FRONT_DIR / "js", fname)

    @app.get("/css/<path:fname>")
    def _css(fname):
        return send_from_directory(FRONT_DIR / "css", fname)

    @app.get("/robots.txt")
    def _robots():
        p = FRONT_DIR / "robots.txt"
        return send_from_directory(FRONT_DIR, "robots.txt") if p.exists() else ("", 204)

    @app.get("/favicon.ico")
    def _favicon():
        p = FRONT_DIR / "favicon.ico"
        return send_from_directory(FRONT_DIR, "favicon.ico") if p.exists() else ("", 204)
