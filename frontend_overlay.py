import os, re, datetime
from wsgiref.util import FileWrapper

class FrontendOverlay:
    def __init__(self, app, root="frontend", ads_client=None):
        self.app = app
        self.root = os.path.abspath(root)
        self.ads_client = ads_client

    def _read(self, rel):
        p = os.path.join(self.root, rel)
        if not os.path.isfile(p):
            return None, None
        with open(p, "rb") as f:
            b = f.read()
        try:
            s = b.decode("utf-8", "strict")
            return s, "text/html; charset=utf-8"
        except Exception:
            return b, "application/octet-stream"

    def _inject_if_needed(self, html):
        s = html

        # hotfix marker
        if "p12-hotfix-v5" not in s:
            s = s.replace("<head>", "<head>\n<meta name=\"x-p12-hotfix\" content=\"p12-hotfix-v5\">", 1)

        # AdSense (solo si falta)
        if self.ads_client and "adsbygoogle.js" not in s:
            tag = f'<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client={self.ads_client}" crossorigin="anonymous"></script>'
            s = re.sub(r"</head>", tag + "\n</head>", s, flags=re.I, count=1)

        # Bloque de métricas (solo si falta .views)
        if 'class="views"' not in s:
            block = '''
<div id="p12-stats" style="opacity:.9;margin-top:1rem;font-size:14px">
  <span class="views">0</span> 👁️
  <span class="likes">0</span> ❤️
  <span class="reports">0</span> 🚩
</div>'''
            if re.search(r"</footer>", s, flags=re.I):
                s = re.sub(r"</footer>", block + "\n</footer>", s, flags=re.I, count=1)
            else:
                s = re.sub(r"</body>", block + "\n</body>", s, flags=re.I, count=1)

        # Evitar SW/cachés viejas
        s = re.sub(r"serviceWorker\.register\(.*?\);\s*", "", s, flags=re.S)
        return s

    def __call__(self, environ, start_response):
        path = environ.get("PATH_INFO", "/") or "/"
        method = environ.get("REQUEST_METHOD", "GET").upper()

        if method == "GET" and path in ("/", "/terms", "/privacy"):
            rel = "index.html" if path == "/" else path.strip("/") + ".html"
            html, ctype = self._read(rel)
            if html is not None:
                if ctype.startswith("text/html"):
                    html = self._inject_if_needed(html)
                    body = html.encode("utf-8")
                else:
                    body = html
                headers = [
                    ("Content-Type", ctype),
                    ("Cache-Control", "no-store, max-age=0"),
                    ("X-Frontend-Overlay", "fe-v1"),
                    ("X-Served-File", rel),
                ]
                start_response("200 OK", headers)
                return [body]
        # Default: delega al app real
        return self.app(environ, start_response)
