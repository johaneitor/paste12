from flask import Blueprint, send_from_directory
from pathlib import Path

def _front_dir():
    pkg = Path(__file__).resolve().parent
    for c in (pkg/"frontend", pkg.parent/"frontend", Path.cwd()/"frontend"):
        if c.exists(): return c
    return pkg/"frontend"

FRONT_DIR = _front_dir()
webui = Blueprint("webui", __name__)

@webui.get("/")
def index(): return send_from_directory(FRONT_DIR, "index.html")

@webui.get("/js/<path:fname>")
def js(fname): return send_from_directory(FRONT_DIR/"js", fname)

@webui.get("/css/<path:fname>")
def css(fname): return send_from_directory(FRONT_DIR/"css", fname)

@webui.get("/robots.txt")
def robots():
    p = FRONT_DIR/"robots.txt"
    return (send_from_directory(FRONT_DIR,"robots.txt") if p.exists() else ("",204))

@webui.get("/favicon.ico")
def favicon():
    p = FRONT_DIR/"favicon.ico"
    return (send_from_directory(FRONT_DIR,"favicon.ico") if p.exists() else ("",204))

def ensure_webui(app):
    """Idempotente: registra el blueprint si no está."""
    try:
        if "webui.index" not in app.view_functions:
            app.register_blueprint(webui)
    except Exception:
        pass
