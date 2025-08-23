from flask import Flask, jsonify
try:
    from backend import create_app as _factory  # type: ignore
except Exception:
    _factory = None

# Construir app (factory preferida)
if _factory:
    app: Flask = _factory()  # type: ignore[call-arg]
else:
    from backend import app as _app  # type: ignore
    app = _app

# Frontend (idempotente)
try:
    from backend.webui import ensure_webui  # type: ignore
    ensure_webui(app)
except Exception:
    pass

# API real: registrar SIEMPRE el blueprint de backend.routes
try:
    from backend.routes import api as api_bp  # type: ignore
    # Evitar sombras: si había un blueprint 'api' residual, limpiamos su referencia
    if "api" in app.blueprints:
        app.blueprints.pop("api", None)
    app.register_blueprint(api_bp)  # type: ignore[attr-defined]
except Exception as e:
    # Si fallara el import, exponer el motivo
    @app.get("/__api_import_error")
    def __api_import_error():
        return jsonify({"ok": False, "where": "import backend.routes", "error": str(e)}), 500
