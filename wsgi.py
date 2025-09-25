from __future__ import annotations
from flask import Flask

# 1) Cargar app desde la factory principal si existe; si falla, intentar fallback conocido.
try:
    from backend import create_app  # type: ignore
    app = create_app()
except Exception:
    try:
        from backend.factory_stable import create_app as _cf  # type: ignore
        app = _cf()
    except Exception:
        app = Flask(__name__)

# 2) Registrar blueprint de frontend si está disponible (idempotente)
try:
    from backend.front_serve import front_bp  # type: ignore
    # Flask evita duplicados internamente; si ya está, no rompe.
    app.register_blueprint(front_bp)
except Exception:
    pass

# 3) Export requerido por Gunicorn
application = app
