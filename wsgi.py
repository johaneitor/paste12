# wsgi.py — entrypoint determinista para Gunicorn (Render)
# Intenta backend.create_app() y cae a wsgiapp._resolve_app() sólo si hace falta.
from typing import Any, Callable

application = None  # type: ignore
app = None          # alias

try:
    # Camino moderno (si existe backend con factoría)
    from backend import create_app as _factory  # type: ignore
    application = _factory()                     # Flask app / WSGI callable
except Exception:
    try:
        # Fallback: usa el resolutor interno si está presente
        from wsgiapp import _resolve_app  # type: ignore
        application = _resolve_app()
    except Exception as e:  # pragma: no cover
        # Dejar trazas claras si algo va mal
        import sys, traceback
        print("[wsgi] FATAL: no pude construir la app WSGI", file=sys.stderr)
        traceback.print_exc()

# Exportar alias 'app' además de 'application' (soporta wsgi:app o wsgi:application)
app = application  # type: ignore
