from typing import Optional
from flask import Flask, jsonify

# 1) Construir la app: preferir factory si existe
_app: Optional[Flask] = None
try:
    from backend import create_app as _factory  # type: ignore
    _app = _factory()  # type: ignore[misc]
except Exception:
    _app = None

if _app is None:
    from backend import app as _fallback_app  # type: ignore
    _app = _fallback_app

app: Flask = _app  # type: ignore[assignment]

# 2) Adjuntar frontend (idempotente)
try:
    from backend.webui import ensure_webui  # type: ignore
    ensure_webui(app)
except Exception:
    pass

# 3) Registrar SIEMPRE la API real
try:
    from backend.routes import api as api_bp  # type: ignore
    if "api" in app.blueprints:
        app.blueprints.pop("api", None)
    app.register_blueprint(api_bp)  # type: ignore[attr-defined]
except Exception as e:
    @app.get("/__api_import_error")
    def __api_import_error():
        return jsonify({"ok": False, "where": "import backend.routes", "error": str(e)}), 500

# 4) Pequeño endpoint de diagnóstico
@app.get("/__whoami")
def __whoami():
    rules = sorted([r.rule for r in app.url_map.iter_rules()])
    return {
        "blueprints": list(app.blueprints.keys()),
        "routes_sample": rules[:60],
        "has_detail_routes": any(r.startswith("/api/notes/<") for r in rules),
    }
