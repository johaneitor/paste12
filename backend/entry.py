from flask import Flask
from pathlib import Path

# 1) Construir app (factory si existe; si no, app global)
try:
    from backend import create_app as _factory  # type: ignore
except Exception:
    _factory = None

if _factory:
    app: Flask = _factory()  # type: ignore[call-arg]
else:
    from backend import app as _app  # type: ignore
    app = _app

# 2) Adjuntar frontend (idempotente)
try:
    from backend.webui import ensure_webui  # type: ignore
    ensure_webui(app)  # no rompe si ya estaba
except Exception:
    pass

# 3) Registrar SIEMPRE el blueprint REAL de API (sin fallback)
try:
    from backend.routes import api as api_bp  # type: ignore
    if 'api' not in app.blueprints:
        app.register_blueprint(api_bp)  # type: ignore[attr-defined]
except Exception as e:
    # Si falla el import, exponer diagnóstico explícito
    @app.get("/__api_import_error")
    def __api_import_error():
        return {"ok": False, "where": "entry import backend.routes", "error": str(e)}, 500

# 4) Endpoint de introspección rápida
@app.get("/__whoami")
def __whoami():
    bp = app.blueprints.get('api')
    return {
        "blueprints": list(app.blueprints.keys()),
        "api_bp_import_name": getattr(bp, "import_name", None),
        "has_notes_detail_routes": any(r.rule.startswith("/api/notes/<") for r in app.url_map.iter_rules()),
    }
