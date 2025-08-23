# Bridge para entornos que arrancan con "wsgi:app"
try:
    from backend.entry import app as app  # usa nuestro entry que registra el webui
except Exception:
    # Fallback a app global del paquete (igual queda API viva)
    from backend import app as app  # type: ignore
