from flask import Blueprint, send_from_directory
from pathlib import Path

# Detecta carpeta frontend en varios layouts (repo root o dentro de backend/)
PKG = Path(__file__).resolve().parent
CANDIDATES = [
    PKG / "frontend",
    PKG.parent / "frontend",
    Path.cwd() / "frontend",
]
for _c in CANDIDATES:
    if _c.exists():
        FRONT_DIR = _c
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

@webui.route("/robots.txt", methods=["GET"])
def robots():
    return send_from_directory(FRONT_DIR, "robots.txt")

@webui.route("/favicon.ico", methods=["GET"])
def favicon():
    p = FRONT_DIR / "favicon.ico"
    if p.exists():
        return send_from_directory(FRONT_DIR, "favicon.ico")
    return ("", 204)

@webui.route("/privacy.html", methods=["GET"])
def privacy():
    return send_from_directory(FRONT_DIR, "privacy.html")

@webui.route("/terms.html", methods=["GET"])
def terms():
    return send_from_directory(FRONT_DIR, "terms.html")
