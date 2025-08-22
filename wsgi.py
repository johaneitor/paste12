# wsgi.py — EntryPoint único para Render/Procfile
# Crea o toma la app y registra el blueprint del frontend de forma defensiva.
try:
    # Caso 1: backend expone app global
    from backend import app as _app
except Exception:
    # Caso 2: backend expone factory create_app
    from backend import create_app as _factory
    _app = _factory()

# Registrar blueprint webui (index, /js, /css, favicon) si no está
try:
    from backend.webui import webui
    if 'webui' not in _app.blueprints:
        _app.register_blueprint(webui)
except Exception:
    # Si falta el frontend, no romper el API
    pass

# WSGI target
app = _app
