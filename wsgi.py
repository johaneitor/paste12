from __future__ import annotations

"""WSGI entrypoint with safe index injection.

Exports `application` compatible with `gunicorn wsgi:application`.
Avoids regex; performs simple string insertions for index flags.
"""

import os
from backend import create_app


def _guess_commit() -> str:
    for k in ("RENDER_GIT_COMMIT", "GIT_COMMIT", "SOURCE_COMMIT", "COMMIT_SHA"):
        v = os.environ.get(k)
        if v:
            return v
    return "unknown"


def _read_index_text() -> str:
    root = os.path.dirname(os.path.abspath(__file__))
    candidates = [
        os.path.join(root, "backend", "frontend", "index.html"),
        os.path.join(root, "backend", "static", "index.html"),
        os.path.join(root, "public", "index.html"),
        os.path.join(root, "frontend", "index.html"),
        os.path.join(root, "index.html"),
    ]
    for p in candidates:
        try:
            if p and os.path.isfile(p):
                with open(p, "r", encoding="utf-8") as f:
                    return f.read()
        except Exception:
            pass
    return "<!doctype html><html><head></head><body>paste12</body></html>"


def _inject_index_flags(html: str) -> str:
    # Ensure meta commit
    if 'name="p12-commit"' not in html and "<head>" in html:
        html = html.replace(
            "<head>",
            f"<head>\n<meta name=\"p12-commit\" content=\"{_guess_commit()}\" />\n",
        )
    # Ensure safe shim marker
    if "p12-safe-shim" not in html and "<head>" in html:
        html = html.replace(
            "<head>",
            "<head>\n<meta name=\"p12-safe-shim\" content=\"1\" />\n",
        )
    # Ensure body data-single flag
    if "<body" in html and "data-single=" not in html:
        html = html.replace("<body", "<body data-single=\"1\"")
    # Ensure notes list container exists for FE to render into
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
    # Defensive: do not transform braces. Altering '{' or '}' can break
    # legitimate CSS/JS/template content. We never call .format() on this
    # HTML, so keep it intact to avoid introducing errors.
    return html


def _wrap_with_index_middleware(app):
    def _wsgi(environ, start_response):
        path = environ.get("PATH_INFO", "/")
        if path in ("/", "/index.html"):
            html = _inject_index_flags(_read_index_text())
            body = html.encode("utf-8")
            headers = [
                ("Content-Type", "text/html; charset=utf-8"),
                ("Cache-Control", "no-store"),
                ("Content-Length", str(len(body))),
            ]
            # Apply security headers here as the WSGI wrapper bypasses Flask's
            # after_request hooks. This keeps behavior consistent with
            # backend factory when P12_SECURE_HEADERS is enabled.
            try:
                if os.environ.get("P12_SECURE_HEADERS", "0") == "1":
                    headers.extend([
                        ("Strict-Transport-Security", "max-age=31536000; includeSubDomains; preload"),
                        ("X-Frame-Options", "DENY"),
                        ("X-Content-Type-Options", "nosniff"),
                        ("Referrer-Policy", "no-referrer"),
                    ])
            except Exception:
                pass
            start_response("200 OK", headers)
            return [body]
        return app(environ, start_response)

    return _wsgi


application = _wrap_with_index_middleware(create_app())
