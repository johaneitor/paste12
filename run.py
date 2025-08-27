from __future__ import annotations

import os
from flask import Flask, jsonify, send_from_directory
from backend import init_extensions, db

app = Flask(__name__, static_folder="public", static_url_path="")

# --- Auto create DB (idempotente) ---
try:
    from backend import db
    with app.app_context():
        db.create_all()
        # Nota: create_all es segura (no pisa tablas existentes).
        print("~ Auto create DB: OK")
except Exception as _e:
    try:
        print("~ Auto create DB falló:", _e)
    except Exception:
        pass
# --- Fin auto create DB ---


# Inicializar extensiones (db, limiter, etc.)
init_extensions(app)

# Cargar modelos para que create_all conozca las tablas
try:
    import backend.models  # noqa: F401
except Exception as e:
    try:
        app.logger.error("Error importando modelos: %r", e)
    except Exception:
        pass

# Crear tablas si no existen (no rompe si ya existen)
try:
    with app.app_context():
        db.create_all()
except Exception as e:
    try:
        app.logger.error("Error en create_all: %r", e)
    except Exception:
        pass

# Registrar blueprint API (si existe)
try:
    from backend.routes import bp as api_bp
    if api_bp.name not in app.blueprints:
        app.register_blueprint(api_bp, url_prefix="/api")
except Exception as e:
    try:
        app.logger.error("No se pudo registrar blueprint API: %r", e)
    except Exception:
        pass

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

if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8000"))
    host = os.environ.get("HOST", "0.0.0.0")
    app.run(host=host, port=port)
