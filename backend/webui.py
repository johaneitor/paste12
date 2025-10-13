from flask import Blueprint, send_from_directory
from pathlib import Path

def _discover_front_dir():
    pkg_dir = Path(__file__).resolve().parent
    candidates = [
        pkg_dir / "frontend",          # backend/frontend
        pkg_dir.parent / "frontend",   # <repo>/frontend
        Path.cwd() / "frontend",       # fallback
    ]
    for c in candidates:
        if c.exists():
            return c
    return candidates[0]

FRONT_DIR = _discover_front_dir()
webui = Blueprint("webui", __name__)

@webui.get("/")
def index():
    return send_from_directory(FRONT_DIR, "index.html")

@webui.get("/js/<path:fname>")
def js(fname: str):
    return send_from_directory(FRONT_DIR / "js", fname)

@webui.get("/css/<path:fname>")
def css(fname: str):
    return send_from_directory(FRONT_DIR / "css", fname)

@webui.get("/robots.txt")
def robots():
    p = FRONT_DIR / "robots.txt"
    return (send_from_directory(FRONT_DIR, "robots.txt") if p.exists() else ("", 204))

@webui.get("/favicon.ico")
def favicon():
    p = FRONT_DIR / "favicon.ico"
    return (send_from_directory(FRONT_DIR, "favicon.ico") if p.exists() else ("", 204))

def ensure_webui(app):
    """Idempotente: registra el blueprint sólo si falta y no hay rutas canónicas.

    Evita duplicar la ruta '/' cuando ya existe un frontend canónico (p. ej. 'front_bp').
    """
    try:
        # Si el blueprint canónico ya expone '/', no registrar este fallback
        if "front_bp.index" in app.view_functions:
            return
        # Si ya hay alguna regla para '/', evitar duplicación de ruta
        try:
            if any(str(r.rule) == "/" for r in app.url_map.iter_rules()):
                return
        except Exception:
            pass
        if "webui.index" not in app.view_functions:
            app.register_blueprint(webui)
    except Exception as exc:
        app.logger.warning("[webui] register failed: %r", exc)


# --- Páginas legales ---
try:
    from flask import send_from_directory
    from pathlib import Path as _Path
    _FD = _Path(__file__).with_name("frontend") / "legal"

    @webui.route("/terms", methods=["GET"])
    def terms():
        p = _FD / "terms.html"
        return (send_from_directory(str(_FD), "terms.html") if p.exists() else ("", 204))

    @webui.route("/privacy", methods=["GET"])
    def privacy():
        p = _FD / "privacy.html"
        return (send_from_directory(str(_FD), "privacy.html") if p.exists() else ("", 204))
except Exception as exc:
    # avoid breaking app startup due to missing optional legal pages
    import logging as _logging
    _logging.getLogger(__name__).warning("[webui.legal] disabled: %r", exc)
