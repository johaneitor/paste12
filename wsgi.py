from __future__ import annotations
import os
from flask import Flask, jsonify, send_from_directory

# App base para Render (WSGI)
app = Flask(__name__, static_folder="public", static_url_path="")

# Config DB (coincidir con tu app)
app.config["SQLALCHEMY_DATABASE_URI"] = os.environ.get("DATABASE_URL", "sqlite:///app.db")
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

# Inicializar DB si el paquete expone 'db'
db = None
try:
    from backend import db as _db
    _db.init_app(app)
    db = _db
except Exception as e:
    print("~ wsgi: db.init_app skipped:", e)

def _register_api(app: Flask) -> str|None:
    # 1) Intentar blueprint ya existente en backend.routes
    try:
        from backend.routes import bp as api_bp
        app.register_blueprint(api_bp, url_prefix="/api")
        return "backend.routes:bp"
    except Exception as e1:
        # 2) Intentar función register_api de routes_notes
        try:
            from backend.routes_notes import register_api
            register_api(app)
            return "backend.routes_notes:register_api"
        except Exception as e2:
            # 3) Fallback: blueprint mínimo en backend.api
            try:
                from backend.api import api as api_bp
                app.register_blueprint(api_bp, url_prefix="/api")
                return "backend.api:api"
            except Exception as e3:
                print("~ wsgi: no API registered:", e1, "|", e2, "|", e3)
                return None

api_src = _register_api(app)

# Health
@app.get("/api/health")
def health():
    return jsonify(ok=True, note="wsgiapp", api=bool(api_src), api_src=api_src)

# Static helpers (opcional)
@app.get("/")
def static_root():
    try:
        return app.send_static_file("index.html")
    except Exception:
        return jsonify(ok=True, note="root")

@app.get("/<path:filename>")
def static(filename):
    try:
        return send_from_directory(app.static_folder, filename)
    except Exception:
        return jsonify(error="static_not_found", file=filename), 404

# Auto create DB (seguro / idempotente)
try:
    if db is not None:
        with app.app_context():
            db.create_all()
            print("~ wsgi: Auto create DB OK")
except Exception as _e:
    print("~ wsgi: Auto create DB failed:", _e)
