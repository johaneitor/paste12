from __future__ import annotations
import os
from backend import create_app

app = create_app()



try:

    from backend.webui import webui

    app.register_blueprint(webui)

except Exception:

    pass

# === Static frontend routes (index & JS) — registrado tras crear app ===
try:
    from flask import send_from_directory
    from pathlib import Path as _Path
    # FRONT_DIR relativo a este archivo (raíz del repo)
    FRONT_DIR = (_Path(__file__).resolve().parent / "frontend").resolve()

    @app.route("/", methods=["GET"])
    def root_index():
        return send_from_directory(FRONT_DIR, "index.html")

    @app.route("/js/<path:fname>", methods=["GET"])
    def static_js(fname):
        return send_from_directory(FRONT_DIR / "js", fname)

    @app.route("/favicon.ico", methods=["GET"])
    def favicon_ico():
        p = FRONT_DIR / "favicon.ico"
        if p.exists():
            return send_from_directory(FRONT_DIR, "favicon.ico")
        return ("", 204)
except Exception:
    # Si falta el frontend en el deploy, no romper el API
    pass

if __name__ == "__main__":
    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", "8000"))
    app.run(host=host, port=port)
