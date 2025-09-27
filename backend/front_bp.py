import os
from flask import Blueprint, send_from_directory, current_app

front_bp = Blueprint("front_bp", __name__)
BASE = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FRONT_DIR = os.path.join(BASE, "frontend")

@front_bp.route("/", methods=["GET"])
def index():
    p = os.path.join(FRONT_DIR, "index.html")
    if not os.path.isfile(p):
        current_app.logger.warning("frontend/index.html no encontrado, devolviendo fallback")
        return "<!doctype html><title>Paste12</title><h1>Paste12</h1>", 200
    return send_from_directory(FRONT_DIR, "index.html")

@front_bp.route("/terms", methods=["GET"])
def terms():
    f = "terms.html"
    return send_from_directory(FRONT_DIR, f) if os.path.isfile(os.path.join(FRONT_DIR, f)) else ("<h1>Términos</h1>", 200)

@front_bp.route("/privacy", methods=["GET"])
def privacy():
    f = "privacy.html"
    return send_from_directory(FRONT_DIR, f) if os.path.isfile(os.path.join(FRONT_DIR, f)) else ("<h1>Privacidad</h1>", 200)
