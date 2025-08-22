import os

# Intenta usar factory; si no, usa app global
try:
    from backend import create_app as _factory
    app = _factory()
except Exception:
    from backend import app  # type: ignore

# Registro defensivo del blueprint del frontend (por si la factory no lo hizo)
try:
    from backend.webui import webui
    if 'webui' not in app.blueprints:  # type: ignore
        app.register_blueprint(webui)  # type: ignore
except Exception:
    pass
