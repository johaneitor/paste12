from flask import Flask, jsonify
try:
    from backend import create_app as _factory  # type: ignore
except Exception:
    _factory = None

if _factory:
    app: Flask = _factory()  # type: ignore[call-arg]
else:
    from backend import app as _app  # type: ignore
    app = _app

# Frontend
try:
    from backend.webui import ensure_webui  # type: ignore
    ensure_webui(app)
except Exception:
    pass

# API real
try:
    from backend.routes import api as api_bp  # type: ignore
    if "api" not in app.blueprints:
        app.register_blueprint(api_bp)  # type: ignore[attr-defined]
except Exception as e:
    @app.get("/__api_import_error")
    def __api_import_error():
        return jsonify({"ok": False, "where": "import backend.routes", "error": str(e)}), 500
