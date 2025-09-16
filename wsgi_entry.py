"""
Entry point estable para Gunicorn en Render.
Resuelve el WSGI callable desde wsgiapp aun si se llama distinto a 'app'.
"""
def _resolve_app():
    import wsgiapp
    # A) variable/función ya llamada 'app'
    if hasattr(wsgiapp, "app"):
        return getattr(wsgiapp, "app")
    # B) variable 'application'
    if hasattr(wsgiapp, "application"):
        return getattr(wsgiapp, "application")
    # C) factorías comunes
    for factory in ("create_app", "make_app"):
        if hasattr(wsgiapp, factory):
            fn = getattr(wsgiapp, factory)
            return fn()
    raise RuntimeError("No se encontró WSGI app en wsgiapp (busqué: app, application, create_app, make_app).")
app = _resolve_app()
