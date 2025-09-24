import os
from flask import Response, Blueprint, send_from_directory, current_app

_bp = Blueprint("p12_front", __name__)
_FRONT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "frontend"))

def _html_resp(path, add_signature=True):
    full = os.path.join(_FRONT_DIR, path)
    with open(full, "rb") as f:
        body = f.read()
    resp = Response(body, mimetype="text/html; charset=utf-8")
    # Candado anti-caché y firma de origen
    resp.headers["Cache-Control"] = "no-store, max-age=0"
    if add_signature:
        resp.headers["X-Frontend-Src"] = f"repo:{os.path.relpath(full)}"
    # (Opcional) pista para que cualquier middleware de inyección lo saltee
    resp.headers["X-Skip-Hotfix"] = "1"
    return resp

@_bp.route("/")
def index():
    # Servir EXACTO el index del repo
    return _html_resp("index.html")

@_bp.route("/terms")
def terms():
    return _html_resp("terms.html")

@_bp.route("/privacy")
def privacy():
    return _html_resp("privacy.html")

def init_front_routes(app):
    # Registrar blueprint raíz SIN prefijo
    app.register_blueprint(_bp)
