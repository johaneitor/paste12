from flask import Blueprint, send_from_directory
from pathlib import Path

PKG_DIR = Path(__file__).resolve().parent  # .../backend
CANDIDATES = [
    PKG_DIR / "frontend",          # backend/frontend (usual en Render)
    PKG_DIR.parent / "frontend",   # <repo>/frontend
    Path.cwd() / "frontend",       # fallback
]
for c in CANDIDATES:
    if c.exists():
        FRONT_DIR = c
        break
else:
    FRONT_DIR = CANDIDATES[0]

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
