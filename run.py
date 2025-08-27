from __future__ import annotations

import os
from flask import Flask, jsonify, send_from_directory

# App con estáticos en ./public (sin colisionar endpoint 'static')
app = Flask(__name__, static_folder="public", static_url_path="")

@app.route("/")
def static_root():
    idx = os.path.join(app.static_folder or "", "index.html")
    if idx and os.path.exists(idx):
        return send_from_directory(app.static_folder, "index.html")
    return jsonify({"ok": True})

@app.route("/ads.txt")
def static_ads():
    p = os.path.join(app.static_folder or "", "ads.txt")
    if p and os.path.exists(p):
        return send_from_directory(app.static_folder, "ads.txt")
    return ("", 404)

@app.route("/favicon.ico")
def static_favicon():
    p = os.path.join(app.static_folder or "", "favicon.ico")
    if p and os.path.exists(p):
        return send_from_directory(app.static_folder, "favicon.ico")
    return ("", 404)

# Registrar blueprint API si existe y no está ya registrado
try:
    from backend.routes import bp as api_bp  # backend.routes a su vez importa backend.routes_notes
    if api_bp.name not in app.blueprints:
        app.register_blueprint(api_bp, url_prefix="/api")
except Exception as e:
    # No rompemos el arranque por esto; quedará visible en logs
    try:
        app.logger.error("No se pudo registrar blueprint API: %r", e)
    except Exception:
        pass

if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8000"))
    host = os.environ.get("HOST", "0.0.0.0")
    app.run(host=host, port=port)
