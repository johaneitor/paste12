from flask import Flask, jsonify

try:
    # Importa la app global definida en backend/__init__.py
    from backend import app as app  # type: ignore
except Exception as e:
    # Si fallara, levanta una app mínima con diagnóstico
    app = Flask(__name__)
    @app.get("/__backend_import_error")
    def __backend_import_error():
        return {"ok": False, "where": "import backend", "error": str(e)}, 500

# Adjunta frontend (idempotente)
try:
    from backend.webui import ensure_webui  # type: ignore
    ensure_webui(app)
except Exception:
    pass

# Adjunta SIEMPRE la API real (sin fallback)
try:
    from backend.routes import api as api_bp  # type: ignore
    if "api" in app.blueprints:
        app.blueprints.pop("api", None)
    app.register_blueprint(api_bp)  # type: ignore[attr-defined]
except Exception as e:
    @app.get("/__api_import_error")
    def __api_import_error():
        return {"ok": False, "where": "import backend.routes", "error": str(e)}, 500

# Pequeño whoami para verificar en prod
@app.get("/__whoami")
def __whoami():
    rules = sorted([r.rule for r in app.url_map.iter_rules()])
    return {
        "blueprints": list(app.blueprints.keys()),
        "has_detail_routes": any(r.startswith("/api/notes/<") for r in rules),
        "routes_sample": rules[:60],
    }
