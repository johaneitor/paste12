from importlib import import_module
from flask import Blueprint, jsonify

# Reexporta la app real desde wsgi.py
_w = import_module("wsgi")
app = getattr(_w, "app")

def _has(rule: str, method: str | None = None) -> bool:
    try:
        for r in app.url_map.iter_rules():
            if str(r) == rule:
                return True if method is None else method in r.methods
    except Exception:
        pass
    return False

# Si /api/debug-urlmap no existe, lo agregamos
if not _has("/api/debug-urlmap", "GET"):
    dbg = Blueprint("wsgiapp_bridge_dbg", __name__)
    @dbg.get("/debug-urlmap")
    def _debug_urlmap():
        rules = []
        for r in app.url_map.iter_rules():
            methods = sorted([m for m in r.methods if m not in ("HEAD","OPTIONS")])
            rules.append({"rule": str(r), "endpoint": r.endpoint, "methods": methods})
        return jsonify({"rules": rules, "source": "wsgiapp-bridge"})
    try:
        app.register_blueprint(dbg, url_prefix="/api")
    except Exception:
        pass
