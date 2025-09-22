# Simple export: Gunicorn cargará "wsgi:application"
from contract_shim import application  # type: ignore
try:
    import db_runtime_guards as _dbg
    _dbg.install(application)
except Exception as _e:
    try:
        import sys; print('db guards skipped:', _e, file=sys.stderr)
    except Exception:
        pass

# Ejecución local (opcional)
if __name__ == "__main__":
    try:
        from waitress import serve
        serve(application, listen="0.0.0.0:8080")
    except Exception:
        from wsgiref.simple_server import make_server
        httpd = make_server("0.0.0.0", 8080, application)
        httpd.serve_forever()
