import os
from flask import Blueprint, send_from_directory, current_app, make_response

front_bp = Blueprint("front_bp", __name__)
BASE = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FRONT_DIR = os.path.join(BASE, "frontend")

@front_bp.route("/", methods=["GET"])
def index():
    p = os.path.join(FRONT_DIR, "index.html")
    if not os.path.isfile(p):
        current_app.logger.warning("frontend/index.html no encontrado, devolviendo fallback")
        return "<!doctype html><title>Paste12</title><h1>Paste12</h1>", 200
    # Read file to inject minimal safety meta if missing
    try:
        with open(p, "r", encoding="utf-8") as f:
            html = f.read()
    except Exception:
        html = None

    if html and "p12-commit" not in html:
        # Safe insertion: append meta right after <head> and add body data-single
        head_inject = (
            '<meta name="p12-commit" content="unknown" />\n'
            '<meta name="p12-safe-shim" content="1" />\n'
        )
        if "<head>" in html:
            html = html.replace("<head>", f"<head>\n{head_inject}")
        if "<body" in html and "data-single=" not in html:
            html = html.replace("<body", "<body data-single=\"1\"")
        resp = make_response(html)
        resp.headers["Content-Type"] = "text/html; charset=utf-8"
    else:
        resp = make_response(send_from_directory(FRONT_DIR, "index.html"))
    resp.headers["Cache-Control"] = "no-store, max-age=0"
    return resp

@front_bp.route("/terms", methods=["GET"])
def terms():
    f = "terms.html"
    return send_from_directory(FRONT_DIR, f) if os.path.isfile(os.path.join(FRONT_DIR, f)) else ("<h1>Términos</h1>", 200)

@front_bp.route("/privacy", methods=["GET"])
def privacy():
    f = "privacy.html"
    return send_from_directory(FRONT_DIR, f) if os.path.isfile(os.path.join(FRONT_DIR, f)) else ("<h1>Privacidad</h1>", 200)
