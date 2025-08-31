import os
from flask import Blueprint, send_from_directory, abort

BASE_DIR   = os.path.dirname(__file__)
STATIC_DIR = os.path.join(BASE_DIR, "static")

bp = Blueprint("web", __name__)

def _ok(p): return os.path.isfile(p)

@bp.route("/")
def root_index():
    p = os.path.join(STATIC_DIR, "index.html")
    if _ok(p): return send_from_directory(STATIC_DIR, "index.html")
    abort(404)

@bp.route("/privacy")
def privacy():
    p = os.path.join(STATIC_DIR, "privacy.html")
    if _ok(p): return send_from_directory(STATIC_DIR, "privacy.html")
    abort(404)

@bp.route("/terms")
def terms():
    p = os.path.join(STATIC_DIR, "terms.html")
    if _ok(p): return send_from_directory(STATIC_DIR, "terms.html")
    abort(404)

@bp.route("/css/<path:path>")
def css(path):
    return send_from_directory(os.path.join(STATIC_DIR, "css"), path)

@bp.route("/js/<path:path>")
def js(path):
    return send_from_directory(os.path.join(STATIC_DIR, "js"), path)

@bp.route("/frontend/js/<path:path>")
def front_js(path):
    return send_from_directory(os.path.join(STATIC_DIR, "frontend/js"), path)

@bp.route("/favicon.svg")
def favicon_svg():
    return send_from_directory(STATIC_DIR, "favicon.svg")

@bp.route("/favicon.ico")
def favicon_ico():
    return send_from_directory(STATIC_DIR, "favicon.ico")

@bp.route("/robots.txt")
def robots_txt():
    return send_from_directory(STATIC_DIR, "robots.txt")

@bp.route("/ads.txt")
def ads_txt():
    return send_from_directory(STATIC_DIR, "ads.txt")

# SPA fallback (no invadir /api ni /static-like)
@bp.route("/<path:any_path>")
def spa(any_path: str):
    if any_path.startswith(("api/", "css/", "js/", "frontend/", "static/")):
        abort(404)
    return root_index()
