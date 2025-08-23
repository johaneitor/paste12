from flask import Flask, jsonify
try:
    # Usa la app GLOBAL de backend; evita llamar create_app() para no enganchar wrappers.
    from backend import app as app  # type: ignore
except Exception as e:
    app = Flask(__name__)
    @app.get("/__backend_import_error")
    def __backend_import_error():
        return {"ok": False, "where": "import backend", "error": str(e)}, 500

def _purge_api_rules(app):
    # Quita TODAS las reglas /api/* (fallbacks previos)
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

# Purga y registra la API REAL
_routes_mod = None
try:
    _purge_api_rules(app)
    import backend.routes as _routes_mod  # type: ignore
    app.register_blueprint(_routes_mod.api)  # type: ignore[attr-defined]
except Exception as e:
    @app.get("/__api_import_error")
    def __api_import_error():
        return {"ok": False, "where": "import/register backend.routes", "error": str(e)}, 500

# Diags
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
        "sample": rules[:120],
        "api_module_file": getattr(_routes_mod, "__file__", None),
        "wsgi_file": __file__,
    }

@app.get("/__api_where")
def __api_where():
    rules = sorted([r.rule for r in app.url_map.iter_rules() if str(r.rule).startswith("/api")])
    return {
        "api_rules": rules,
        "api_module_file": getattr(_routes_mod, "__file__", None),
    }
