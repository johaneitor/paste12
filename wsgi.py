# WSGI app para gunicorn: "wsgi:app"
# - Toma la app desde backend.entry (que ya adjunta el frontend)
# - Registra el blueprint real de API si no está
from backend.entry import app as app  # noqa

try:
    from backend.routes import api as api_bp  # blueprint real
    # Evita doble registro si ya estuviera
    if 'api' not in app.blueprints:
        app.register_blueprint(api_bp)
except Exception as e:
    # Ruta de diagnóstico si fallara el import en producción
    @app.get("/__api_import_error")
    def __api_import_error():
        return {"ok": False, "where": "wsgi import backend.routes", "error": str(e)}, 500
