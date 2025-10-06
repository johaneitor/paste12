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
        resp = make_response("<!doctype html><title>Paste12</title><h1>Paste12</h1>", 200)
        resp.headers["Cache-Control"] = "no-cache"
        return resp
    resp = make_response(send_from_directory(FRONT_DIR, "index.html"))
    resp.headers["Cache-Control"] = "no-cache"
    return resp

@front_bp.route("/terms", methods=["GET"])
def terms():
    f = "terms.html"
    if os.path.isfile(os.path.join(FRONT_DIR, f)):
        resp = make_response(send_from_directory(FRONT_DIR, f))
    else:
        resp = make_response("<!doctype html><title>Términos</title><h1>Términos</h1><p>Condiciones básicas.</p>", 200)
    resp.headers["Cache-Control"] = "no-cache"
    return resp

@front_bp.route("/privacy", methods=["GET"])
def privacy():
    f = "privacy.html"
    if os.path.isfile(os.path.join(FRONT_DIR, f)):
        resp = make_response(send_from_directory(FRONT_DIR, f))
    else:
        resp = make_response("<!doctype html><title>Privacidad</title><h1>Privacidad</h1><p>Sin tracking personalizado.</p>", 200)
    resp.headers["Cache-Control"] = "no-cache"
    return resp
