# Entry WSGI para Render
# - Si hay factory: backend.create_app()
# - Si no, usa backend.app
# - En ambos casos registra el blueprint del frontend (backend.webui)

try:
    from backend import create_app as _factory
    app = _factory()
except Exception:
    from backend import app  # noqa: F401

# Registro defensivo del blueprint del frontend
try:
    from backend.webui import webui
    if 'webui' not in app.blueprints:  # type: ignore
        app.register_blueprint(webui)  # type: ignore
        print("[wsgi] webui blueprint registrado", flush=True)
except Exception as e:
    print(f"[wsgi] no pude registrar webui: {e}", flush=True)
