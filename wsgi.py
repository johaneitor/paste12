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
        # Prefer canonical frontend index shipped with the repo
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
    """Enforce minimal flags and SEO on index HTML while preserving content."""
    # Ensure commit meta
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

    # Minimal SEO (non-intrusive)
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
        if 'rel="canonical"' not in html:
            # Use site-root canonical by default to avoid leaking environment
            html = html.replace(
                "</head>",
                "  <link rel=\"canonical\" href=\"/\" />\n</head>",
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

    # Ensure body data-single flag without breaking existing attributes
    if "<body" in html and "data-single=" not in html:
        try:
            idx = html.lower().find("<body")
            if idx != -1:
                end = html.find(">", idx)
                if end != -1:
                    html = html[:end] + " data-single=\"1\"" + html[end:]
        except Exception:
            # Conservative fallback
            html = html.replace("<body>", "<body data-single=\"1\">")

    # Ensure notes list container exists (insert right after <body...>)
    if 'id="notes-list"' not in html:
        if "</main>" in html:
            html = html.replace("</main>", "  <ul id=\"notes-list\"></ul>\n</main>")
        else:
            try:
                idx = html.lower().find("<body")
                if idx != -1:
                    end = html.find(">", idx)
                    if end != -1:
                        html = html[:end+1] + "\n<ul id=\"notes-list\"></ul>\n" + html[end+1:]
            except Exception:
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
