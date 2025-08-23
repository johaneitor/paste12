from flask import Blueprint, send_from_directory
from pathlib import Path

PKG = Path(__file__).resolve().parent
CANDS = [PKG/'frontend', PKG.parent/'frontend', Path.cwd()/'frontend']
for c in CANDS:
    if c.exists():
        FRONT_DIR = c
        break
else:
    FRONT_DIR = CANDS[0]

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
