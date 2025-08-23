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

# Frontend
try:
    from backend.webui import ensure_webui  # type: ignore
    ensure_webui(app)
except Exception:
    pass

# API real (SIN fallback 501)
try:
    from backend.routes import api as api_bp  # type: ignore
    # Si por alguna razón ya hay un blueprint 'api' previo, lo reemplazamos:
    if "api" in app.blueprints:
        # Nota: Flask no tiene "unregister", pero aseguramos que el que quede
        # montado sea el real registrándolo después del build (fresh deploy).
        app.blueprints.pop("api", None)
    app.register_blueprint(api_bp)  # type: ignore[attr-defined]
except Exception as e:
    # Si fallara el import, exponer un diags para verlo rápido
    @app.get("/__api_import_error")
    def __api_import_error():
        return jsonify({"ok": False, "where": "import backend.routes", "error": str(e)}), 500
