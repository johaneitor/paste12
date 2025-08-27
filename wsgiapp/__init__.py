# Paquete shim: si gunicorn arranca wsgiapp:app, redirigimos al app de wsgi.py
from importlib import import_module

_w = import_module("wsgi")        # importa el módulo wsgi.py del repo
app = getattr(_w, "app")          # reexporta app (gunicorn verá wsgiapp:app)

# (Opcional) asegura que /api/notes exista si el app aún no lo registró
try:
    has_notes = any(str(r.rule) == "/api/notes" for r in app.url_map.iter_rules())
    if not has_notes and hasattr(_w, "bp_forced"):
        app.register_blueprint(getattr(_w, "bp_forced"), url_prefix="/api")
except Exception:
    pass
