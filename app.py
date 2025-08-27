from __future__ import annotations
import os
from flask import Flask, jsonify
from backend import create_app, db

VER = "triplex-v2"

def _has_rule(app, rule: str, method: str) -> bool:
    try:
        for r in app.url_map.iter_rules():
            if str(r) == rule and method.upper() in r.methods:
                return True
    except Exception:
        pass
    return False

app: Flask = create_app()

# Registrar /api/notes si faltara (idempotente)
try:
    from backend.routes_notes import register_api
    if not (_has_rule(app, "/api/notes", "GET") and _has_rule(app, "/api/notes", "POST")):
        register_api(app)
except Exception:
    pass

# Health con marca
if not _has_rule(app, "/api/health", "GET"):
    @app.get("/api/health")
    def _health():
        ok_api = _has_rule(app, "/api/notes", "GET") and _has_rule(app, "/api/notes", "POST")
        return jsonify(ok=True, note="triplex", ver=VER, api=ok_api)

# create_all no falla si ya existen tablas
try:
    with app.app_context():
        db.create_all()
except Exception:
    pass

if __name__ == "__main__":
    host = os.environ.get("HOST", "0.0.0.0")
    port = int(os.environ.get("PORT", "8000"))
    app.run(host=host, port=port)
