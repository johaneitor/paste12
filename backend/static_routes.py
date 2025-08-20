import os
from flask import Blueprint, current_app, send_from_directory, abort

bp = Blueprint("static_files", __name__)

@bp.get("/favicon.ico")
def favicon():
    return send_from_directory(current_app.static_folder, "favicon.svg", mimetype="image/svg+xml")

@bp.get("/ads.txt")
def ads_txt():
    return send_from_directory(current_app.static_folder, "ads.txt", mimetype="text/plain")

@bp.route("/")
def index():
    return send_from_directory(current_app.static_folder, "index.html")

@bp.route("/<path:path>")
def static_proxy(path: str):
    # No interceptar API
    if path.startswith("api/"):
        abort(404)
    full = os.path.join(current_app.static_folder, path)
    if os.path.isfile(full):
        # Sirve cualquier archivo que exista dentro de /frontend
        return send_from_directory(current_app.static_folder, path)
    # SPA fallback / rutas desconocidas del frontend → index.html
    return send_from_directory(current_app.static_folder, "index.html")
