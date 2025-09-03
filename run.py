import os, mimetypes

try:
    # Reutilizamos la app ya creada en tu paquete backend
    from backend import app  # debe existir backend/__init__.py o backend/app.py con "app = Flask(__name__)"
except Exception as e:
    raise RuntimeError(f"[run.py] No pude importar backend.app: {e}")

def _read_index_bytes():
    """Devuelve (path, bytes) del index pastel; orden de preferencia estable."""
    root = os.path.dirname(os.path.abspath(__file__))
    candidates = [
        os.path.join(root, "backend", "static", "index.html"),
        os.path.join(root, "public",  "index.html"),
        os.path.join(root, "frontend","index.html"),
        os.path.join(root, "index.html"),
    ]
    for p in candidates:
        if p and os.path.isfile(p):
            with open(p, "rb") as f:
                return p, f.read()
    # Fallback mínimo embebido (si faltan archivos)
    fallback = b"""<!doctype html><html><head><meta charset="utf-8"><title>paste12</title></head>
<body style="font-family: system-ui, sans-serif; margin: 2rem;">
<h1>paste12</h1><p>Backend vivo. Revisa backend/static/index.html</p>
</body></html>"""
    return None, fallback

def _install_root_index_once(flask_app):
    """Registra '/' y '/index.html' sólo si no están. Evita 'View function mapping is overwriting...'."""
    if "root_index" in flask_app.view_functions:
        print("[app] Nota: root_index ya estaba registrado; no lo toco.")
        return

    from flask import make_response

    idx_path, idx_bytes = _read_index_bytes()
    ctype = mimetypes.guess_type(idx_path or "index.html")[0] or "text/html"

    def root_index():
        resp = make_response(idx_bytes)
        resp.headers["Content-Type"]  = f"{ctype}; charset=utf-8"
        resp.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
        resp.headers["X-Index-Source"] = "app-base"
        return resp

    # endpoint principal
    flask_app.add_url_rule("/", endpoint="root_index", view_func=root_index, methods=["GET","HEAD"])
    # alias con otro nombre de endpoint para no colisionar
    flask_app.add_url_rule("/index.html", endpoint="root_index_alias", view_func=root_index, methods=["GET","HEAD"])
    print("[app] root_index activo (index pastel + no-store)")

# instalar raíz idempotente
_install_root_index_once(app)

if __name__ == "__main__":
    host = os.environ.get("HOST", "0.0.0.0")
    port = int(os.environ.get("PORT", "8000"))
    # No usar debug en producción; esto es sólo para dev local
    app.run(host=host, port=port, debug=False)
