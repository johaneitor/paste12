#!/usr/bin/env bash
set -Eeuo pipefail

python - <<'PY'
from pathlib import Path
p = Path("backend/webui.py")

content = """from flask import Blueprint, send_from_directory
from pathlib import Path

def _discover_front_dir():
    pkg_dir = Path(__file__).resolve().parent  # .../backend
    candidates = [
        pkg_dir / "frontend",          # backend/frontend (Render)
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
    \"\"\"Registra el blueprint si aún no está registrado.\"\"\"
    try:
        if "webui.index" not in app.view_functions:
            app.register_blueprint(webui)
    except Exception:
        # no romper el API si algo falla
        pass
"""
p.write_text(content, encoding="utf-8")
print("webui.py normalizado.")
PY

echo "➤ Commit & push"
git add backend/webui.py
git commit -m "fix(webui): remover decorators duplicados; una regla por endpoint y ensure_webui() estable"
git push origin main
