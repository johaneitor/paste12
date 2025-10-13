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
except Exception as exc:
    app.logger.warning("[webui] ensure_webui failed: %r", exc)

# API real: registrar blueprint de backend.routes si no está presente
try:
    from backend.routes import api_bp as _api_bp  # type: ignore
    if "api" not in app.blueprints:
        app.register_blueprint(_api_bp, url_prefix="/api")  # type: ignore[attr-defined]
except Exception as e:
    # Si fallara el import, exponer el motivo
    @app.get("/__api_import_error")
    def __api_import_error():
        return jsonify({"ok": False, "where": "import backend.routes", "error": str(e)}), 500
