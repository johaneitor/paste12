# WSGI para gunicorn: usa la app real y SOLO el blueprint real.
# Si falla el import del blueprint, expone /__api_import_error (500) para ver el motivo.
from backend.entry import app as app  # noqa

try:
    from backend.routes import api as api_bp  # blueprint real con url_prefix="/api"
    if 'api' not in app.blueprints:
        app.register_blueprint(api_bp)
except Exception as e:
    @app.get("/__api_import_error")
    def __api_import_error():
        return {"ok": False, "where": "wsgi import backend.routes", "error": str(e)}, 500
