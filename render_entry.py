from wsgiapp import _resolve_app as _factory
# Construimos la app UNA vez al importar este módulo (y NO volvemos a invocar _resolve_app)
_app = _factory()
def app(environ, start_response):
    return _app(environ, start_response)
