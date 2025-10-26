import os
import re
import glob
import mimetypes
from flask import Blueprint, send_from_directory, current_app, make_response, request, redirect

front_bp = Blueprint("front_bp", __name__)
# Servir UI desde backend/frontend (canónico)
FRONT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "frontend"))

# Asegurar MIME correcto para JS/SVG en algunos entornos
mimetypes.add_type('application/javascript', '.js')
mimetypes.add_type('image/svg+xml', '.svg')

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
        # Minimal SEO: title, description, favicon, canonical and OG if missing
        if "<head>" in html:
            if "<title>" not in html:
                html = html.replace("<head>", "<head>\n<title>Paste12 — notas efímeras</title>\n")
            if 'name="description"' not in html:
                html = html.replace(
                    "<head>",
                    "<head>\n<meta name=\"description\" content=\"Comparte notas efímeras de forma simple y segura.\" />\n",
                )
            if 'rel="icon"' not in html and 'rel="shortcut icon"' not in html:
                html = html.replace(
                    "</head>",
                    "  <link rel=\"icon\" href=\"/favicon.svg\" />\n</head>",
                )
            # Canonical absoluto y og:url
            try:
                root = (request.url_root or '').rstrip('/')
            except Exception:
                root = ''
            if 'rel="canonical"' not in html:
                html = html.replace(
                    "</head>",
                    f"  <link rel=\\\"canonical\\\" href=\\\"{root}/\\\" />\n</head>",
                )
            if 'property="og:title"' not in html:
                html = html.replace(
                    "</head>",
                    "  <meta property=\"og:title\" content=\"Paste12\" />\n</head>",
                )
            if 'property="og:description"' not in html:
                html = html.replace(
                    "</head>",
                    "  <meta property=\"og:description\" content=\"Notas efímeras, simples y seguras.\" />\n</head>",
                )
            if 'property="og:image"' not in html:
                html = html.replace(
                    "</head>",
                    "  <meta property=\"og:image\" content=\"/img/og.png\" />\n</head>",
                )
            if 'property="og:url"' not in html and root:
                html = html.replace(
                    "</head>",
                    f"  <meta property=\\\"og:url\\\" content=\\\"{root}/\\\" />\n</head>",
                )
            # Twitter cards (si faltan)
            if 'name="twitter:card"' not in html:
                html = html.replace(
                    "</head>",
                    "  <meta name=\"twitter:card\" content=\"summary_large_image\" />\n</head>",
                )
            if 'name="twitter:title"' not in html:
                html = html.replace(
                    "</head>",
                    "  <meta name=\"twitter:title\" content=\"Paste12\" />\n</head>",
                )
            if 'name="twitter:description"' not in html:
                html = html.replace(
                    "</head>",
                    "  <meta name=\"twitter:description\" content=\"Notas efímeras, simples y seguras.\" />\n</head>",
                )
            if 'name="twitter:image"' not in html:
                html = html.replace(
                    "</head>",
                    "  <meta name=\"twitter:image\" content=\"/img/og.png\" />\n</head>",
                )
        # Ensure body data-single flag (preserving existing attributes)
        if "<body" in html and "data-single=" not in html:
            try:
                idx = html.lower().find("<body")
                if idx != -1:
                    end = html.find(">", idx)
                    if end != -1:
                        html = html[:idx] + html[idx:end] + " data-single=\"1\"" + html[end:]
            except Exception:
                # fallback minimal replacement without breaking attributes
                html = html.replace("<body>", "<body data-single=\"1\">")
        # Ensure notes list container exists (insert right after <body...>)
        if 'id="notes-list"' not in html:
            if "</main>" in html:
                html = html.replace("</main>", "  <ul id=\"notes-list\"></ul>\n</main>")
            elif "<body" in html:
                try:
                    idx = html.lower().find("<body")
                    if idx != -1:
                        end = html.find(">", idx)
                        if end != -1:
                            html = html[:end+1] + "\n<ul id=\"notes-list\"></ul>\n" + html[end+1:]
                except Exception:
                    html = html.replace("<body>", "<body>\n<ul id=\"notes-list\"></ul>")
            else:
                html += "\n<ul id=\"notes-list\"></ul>\n"
        # Compute asset base (optional static site CDN/prefix)
        try:
            ASSETS_BASE = (os.environ.get('ASSETS_BASE_URL') or '').rstrip('/')
        except Exception:
            ASSETS_BASE = ''
        def aurl(p: str) -> str:
            return (ASSETS_BASE + p) if ASSETS_BASE else p

        # Optionally rewrite existing asset URLs to ASSETS_BASE_URL for CSS/JS/IMG
        if ASSETS_BASE:
            try:
                # Rewrite href/src attributes for /css/, /js/, /img/ and favicon
                def _rewr(m):
                    pre = m.group('pre')
                    path = m.group('path')  # starts with leading slash
                    return f"{pre}{ASSETS_BASE}{path}"
                html = re.sub(r"(?P<pre>(?:href|src)=[\"'])(?P<path>/(?:css|js|img)/[\w./?=&%-]+)", _rewr, html)
                html = re.sub(r"(?P<pre>(?:href|src)=[\"'])(?P<path>/favicon(?:\.svg|\.ico)?)", _rewr, html)
            except Exception:
                pass

        # Ensure core assets are loaded
        if '/css/actions.css' not in html and "</head>" in html:
            html = html.replace("</head>", f"  <link rel=\\\"stylesheet\\\" href=\\\"{aurl('/css/actions.css')}\\\">\n</head>")
        if '/js/app.js' not in html:
            if "</body>" in html:
                html = html.replace("</body>", f"  <script src=\\\"{aurl('/js/app.js')}\\\" defer></script>\n</body>")
            elif "</head>" in html:
                html = html.replace("</head>", f"  <script src=\\\"{aurl('/js/app.js')}\\\" defer></script>\n</head>")
            else:
                html += f"\n<script src=\\\"{aurl('/js/app.js')}\\\" defer></script>\n"
        else:
            # Garantizar defer si ya existe la etiqueta app.js
            html = html.replace("/js/app.js\"", "/js/app.js\" defer")
        if '/js/actions.js' not in html:
            if "</body>" in html:
                html = html.replace("</body>", f"  <script src=\\\"{aurl('/js/actions.js')}\\\"></script>\n</body>")
            elif "</head>" in html:
                html = html.replace("</head>", f"  <script src=\\\"{aurl('/js/actions.js')}\\\"></script>\n</head>")
            else:
                html += f"\n<script src=\\\"{aurl('/js/actions.js')}\\\"></script>\n"
        if '/js/ads_lazy.js' not in html:
            if "</body>" in html:
                html = html.replace("</body>", f"  <script src=\\\"{aurl('/js/ads_lazy.js')}\\\" defer></script>\n</body>")
            elif "</head>" in html:
                html = html.replace("</head>", f"  <script src=\\\"{aurl('/js/ads_lazy.js')}\\\" defer></script>\n</head>")
            else:
                html += f"\n<script src=\\\"{aurl('/js/ads_lazy.js')}\\\" defer></script>\n"
        # Retirar debug_overlay del HTML generado por el inyectable; se carga sólo con ?debug=1
        html = html.replace('<script src=\"/js/debug_overlay.js\" defer></script>', '')
        resp = make_response(html)
        resp.headers["Content-Type"] = "text/html; charset=utf-8"
    else:
        resp = make_response(send_from_directory(FRONT_DIR, "index.html", conditional=True))
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
        content_type = (resp.headers.get('Content-Type') or '').lower()
        path = (request.path or '')

        def is_asset_path(p: str) -> bool:
            return any(seg in p for seg in ("/css/", "/js/", "/img/", "/assets/", "/favicon."))

        def is_fingerprinted(p: str) -> bool:
            try:
                base = os.path.basename(p.split('?', 1)[0])
                return '-' in base or re.search(r"\.[a-f0-9]{8,}\.", base or '') is not None
            except Exception:
                return False

        if is_asset_path(path) and (('text/css' in content_type) or ('javascript' in content_type) or content_type.startswith('image/')):
            if is_fingerprinted(path) or any(path.endswith(ext) for ext in ('.js', '.css', '.svg', '.woff2')):
                resp.headers['Cache-Control'] = 'public, max-age=31536000, immutable'
            else:
                resp.headers['Cache-Control'] = 'public, max-age=604800'
    except Exception:
        pass
    return resp


# Serve static assets (css/js/img)
@front_bp.route('/css/<path:fname>')
def css(fname: str):
    # Si tenemos ASSETS_BASE_URL configurado, redirigimos permanente a ese host para cache CDN
    assets_base = (os.environ.get('ASSETS_BASE_URL') or '').rstrip('/')
    if assets_base:
        return redirect(f"{assets_base}/css/{fname}", code=301)
    return send_from_directory(os.path.join(FRONT_DIR, 'css'), fname, conditional=True)


@front_bp.route('/js/<path:fname>')
def js(fname: str):
    assets_base = (os.environ.get('ASSETS_BASE_URL') or '').rstrip('/')
    if assets_base:
        return redirect(f"{assets_base}/js/{fname}", code=301)
    return send_from_directory(os.path.join(FRONT_DIR, 'js'), fname, conditional=True)


@front_bp.route('/img/<path:fname>')
def img(fname: str):
    assets_base = (os.environ.get('ASSETS_BASE_URL') or '').rstrip('/')
    if assets_base:
        return redirect(f"{assets_base}/img/{fname}", code=301)
    return send_from_directory(os.path.join(FRONT_DIR, 'img'), fname, conditional=True)


# Compat: servir rutas /assets/* con MIME correcto; intenta mapear a css/js/img
@front_bp.route('/assets/<path:fname>')
def assets(fname: str):
    # Primero, si existe un directorio 'assets', servimos desde ahí
    assets_dir = os.path.join(FRONT_DIR, 'assets')
    target_dir = None
    if os.path.isdir(assets_dir):
        target_dir = assets_dir
    else:
        # Inferir por extensión
        ext = os.path.splitext(fname)[1].lower()
        if ext == '.js':
            target_dir = os.path.join(FRONT_DIR, 'js')
        elif ext == '.css':
            target_dir = os.path.join(FRONT_DIR, 'css')
        elif ext in ('.png', '.jpg', '.jpeg', '.gif', '.svg', '.webp'):
            target_dir = os.path.join(FRONT_DIR, 'img')
        else:
            target_dir = FRONT_DIR

    # Resolver comodines simples tipo index-*.js
    if any(ch in fname for ch in ('*', '?', '[')):
        pattern = os.path.join(target_dir, fname)
        candidates = sorted(glob.glob(pattern))
        if candidates:
            base = os.path.basename(candidates[-1])
            return send_from_directory(target_dir, base, conditional=True)
        # Si no hay match, devolver 404 explícito
        return ("not found", 404)

    return send_from_directory(target_dir, fname, conditional=True)


@front_bp.route('/favicon.ico')
def favicon_ico():
    return send_from_directory(FRONT_DIR, 'favicon.ico', conditional=True)


@front_bp.route('/favicon.svg')
def favicon_svg():
    return send_from_directory(FRONT_DIR, 'favicon.svg', conditional=True)


@front_bp.route('/robots.txt')
def robots_txt():
    return send_from_directory(FRONT_DIR, 'robots.txt')


@front_bp.route('/ads.txt')
def ads_txt():
    return send_from_directory(FRONT_DIR, 'ads.txt')


# Graceful alias: /notes -> redirect to home (UI lives at /)
@front_bp.route('/notes', methods=['GET'])
def notes_redirect():
    try:
        return redirect('/', code=302)
    except Exception:
        return redirect('/')
