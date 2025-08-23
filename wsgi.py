from flask import Flask, jsonify
try:
    from backend import app as app  # usa la app global, evita create_app()
except Exception as e:
    app = Flask(__name__)
    @app.get("/__backend_import_error")
    def __backend_import_error():
        return {"ok": False, "where": "import backend", "error": str(e)}, 500

def _purge_api_rules(app):
    # elimina TODAS las reglas /api/* (para quitar fallbacks que se registraron antes)
    rules = list(app.url_map.iter_rules())
    for r in rules:
        if str(r.rule).startswith("/api"):
            try:
                app.url_map._rules.remove(r)
            except ValueError:
                pass
            lst = app.url_map._rules_by_endpoint.get(r.endpoint)
            if lst and r in lst:
                lst.remove(r)
            if not app.url_map._rules_by_endpoint.get(r.endpoint):
                app.view_functions.pop(r.endpoint, None)

# Frontend idempotente
try:
    from backend.webui import ensure_webui  # type: ignore
    ensure_webui(app)
except Exception:
    pass

# Purga rutas /api y registra la API REAL
try:
    _purge_api_rules(app)
    from backend.routes import api as api_bp  # type: ignore
    app.register_blueprint(api_bp)  # ahora las reales quedan activas
except Exception as e:
    @app.get("/__api_import_error")
    def __api_import_error():
        return {"ok": False, "where": "import backend.routes", "error": str(e)}, 500

# Diag rápido
@app.get("/__whoami")
def __whoami():
    rules = sorted(
        [{"rule": r.rule, "methods": sorted(r.methods), "endpoint": r.endpoint}
         for r in app.url_map.iter_rules()],
        key=lambda x: x["rule"]
    )
    return {
        "blueprints": sorted(list(app.blueprints.keys())),
        "has_detail_routes": any(r["rule"].startswith("/api/notes/<") for r in rules),
        "routes_sample": rules[:120],
        "wsgi_file": __file__,
    }
