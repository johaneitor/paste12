from flask import Blueprint, send_from_directory
from pathlib import Path

# Detecta dónde está el frontend (soporta deploy con root en 'backend')
PKG_DIR = Path(__file__).resolve().parent  # .../backend
CANDIDATES = [
    PKG_DIR / "frontend",            # backend/frontend (deploy subdir)
    PKG_DIR.parent / "frontend",     # <repo>/frontend (deploy root)
    Path.cwd() / "frontend",         # fallback
]
for _cand in CANDIDATES:
    if _cand.exists():
        FRONT_DIR = _cand
        break
else:
    FRONT_DIR = CANDIDATES[0]

webui = Blueprint("webui", __name__)

@webui.route("/", methods=["GET"])
def index():
    return send_from_directory(FRONT_DIR, "index.html")

@webui.route("/js/<path:fname>", methods=["GET"])
def js(fname):
    return send_from_directory(FRONT_DIR / "js", fname)

@webui.route("/css/<path:fname>", methods=["GET"])
def css(fname):
    return send_from_directory(FRONT_DIR / "css", fname)

@webui.route("/favicon.ico", methods=["GET"])
def favicon():
    p = FRONT_DIR / "favicon.ico"
    if p.exists():
        return send_from_directory(FRONT_DIR, "favicon.ico")
    return ("", 204)

@webui.route("/robots.txt", methods=["GET"])
def robots():
    p = FRONT_DIR / "robots.txt"
    if p.exists():
        return send_from_directory(FRONT_DIR, "robots.txt")
    return ("User-agent: *\nAllow: /\n", 200, {"Content-Type": "text/plain; charset=utf-8"})

@webui.route("/privacy.html", methods=["GET"])
def privacy():
    return send_from_directory(FRONT_DIR, "privacy.html")

@webui.route("/terms.html", methods=["GET"])
def terms():
    return send_from_directory(FRONT_DIR, "terms.html")
