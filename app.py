from __future__ import annotations
import os
from flask import Flask, jsonify
from backend import create_app, db

VER = "triplex-v1"

def _has_rule(app, rule: str, method: str) -> bool:
    try:
        for r in app.url_map.iter_rules():
            if str(r) == rule and method.upper() in r.methods:
                return True
    except Exception:
        pass
    return False

# Construimos la app mediante backend.create_app()
app: Flask = create_app()

# Si /api/notes no existe, registramos la cápsula
api_src = None
if not (_has_rule(app, "/api/notes", "GET") and _has_rule(app, "/api/notes", "POST")):
    try:
        from backend.routes_notes import register_api
        api_src = register_api(app)
    except Exception as _e:
        api_src = f"register_api_failed:{_e}"

# Health con marcador y fuente
if not _has_rule(app, "/api/health", "GET"):
    @app.get("/api/health")
    def _health():
        return jsonify(ok=True, note="triplex", ver=VER, api=_has_rule(app, "/api/notes", "GET"), api_src=api_src)

# Aseguramos create_all (SQLite u otro) — no falla si ya existe
try:
    with app.app_context():
        db.create_all()
except Exception as _e:
    pass

# Soporte para ejecutar localmente (python app.py)
if __name__ == "__main__":
    host = os.environ.get("HOST", "0.0.0.0")
    port = int(os.environ.get("PORT", "8000"))
    app.run(host=host, port=port)
