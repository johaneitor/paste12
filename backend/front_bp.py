import os
from flask import Blueprint, send_from_directory, current_app, make_response, request

front_bp = Blueprint("front_bp", __name__)
# Servir UI desde backend/frontend (canónico)
FRONT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "frontend"))

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

    if html:
        # Ensure commit meta
        if "p12-commit" not in html:
            if "<head>" in html:
                html = html.replace("<head>", "<head>\n<meta name=\"p12-commit\" content=\"unknown\" />\n")
        # Ensure safe shim meta
        if "p12-safe-shim" not in html and "<head>" in html:
            html = html.replace("<head>", "<head>\n<meta name=\"p12-safe-shim\" content=\"1\" />\n")
        # Ensure body data-single flag
        if "<body" in html and "data-single=" not in html:
            html = html.replace("<body", "<body data-single=\"1\"")
        # Ensure notes list container exists
        if 'id="notes-list"' not in html:
            if "</main>" in html:
                html = html.replace("</main>", "  <ul id=\"notes-list\"></ul>\n</main>")
            elif "<body" in html:
                html = html.replace("<body", "<body>\n<ul id=\"notes-list\"></ul>")
            else:
                html += "\n<ul id=\"notes-list\"></ul>\n"
        # Ensure app.js is loaded
        if '/js/app.js' not in html:
            if "</body>" in html:
                html = html.replace("</body>", "  <script src=\"/js/app.js\" defer></script>\n</body>")
            elif "</head>" in html:
                html = html.replace("</head>", "  <script src=\"/js/app.js\" defer></script>\n</head>")
            else:
                html += "\n<script src=\"/js/app.js\" defer></script>\n"
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


# Static cache headers for assets (allow 7 days caching)
@front_bp.after_request
def _static_cache(resp):
    try:
        p = (resp.headers.get('Content-Type') or '').lower()
        path = request.path or ''
        if any(seg in path for seg in ("/css/", "/js/", "/img/")):
            if 'text/css' in p or 'javascript' in p or 'image/' in p:
                resp.headers.setdefault('Cache-Control', 'public, max-age=604800')
    except Exception:
        pass
    return resp


# Serve static assets (css/js/img)
@front_bp.route('/css/<path:fname>')
def css(fname: str):
    return send_from_directory(os.path.join(FRONT_DIR, 'css'), fname)


@front_bp.route('/js/<path:fname>')
def js(fname: str):
    return send_from_directory(os.path.join(FRONT_DIR, 'js'), fname)


@front_bp.route('/img/<path:fname>')
def img(fname: str):
    return send_from_directory(os.path.join(FRONT_DIR, 'img'), fname)


@front_bp.route('/favicon.ico')
def favicon_ico():
    return send_from_directory(FRONT_DIR, 'favicon.ico')


@front_bp.route('/favicon.svg')
def favicon_svg():
    return send_from_directory(FRONT_DIR, 'favicon.svg')


@front_bp.route('/robots.txt')
def robots_txt():
    return send_from_directory(FRONT_DIR, 'robots.txt')


@front_bp.route('/ads.txt')
def ads_txt():
    return send_from_directory(FRONT_DIR, 'ads.txt')
