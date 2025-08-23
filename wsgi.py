# WSGI usado por Render (start command: wsgi:app).
# - NO hay fallback de API.
# - Si falla el import del blueprint real, expone /__api_import_error (500) para ver la excepción.

from backend.entry import app as app  # la app real

try:
    # Blueprint REAL (pref: url_prefix="/api")
    from backend.routes import api as api_bp  # type: ignore
    if 'api' not in app.blueprints:
        app.register_blueprint(api_bp)       # type: ignore
except Exception as e:
    @app.get("/__api_import_error")
    def __api_import_error():
        return {"ok": False, "where": "wsgi import backend.routes", "error": str(e)}, 500
