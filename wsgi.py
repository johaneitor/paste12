# Simple export: Gunicorn cargará "wsgi:application"
from contract_shim import application  # type: ignore

# Ejecución local (opcional)
if __name__ == "__main__":
    try:
        from waitress import serve
        serve(application, listen="0.0.0.0:8080")
    except Exception:
        from wsgiref.simple_server import make_server
        httpd = make_server("0.0.0.0", 8080, application)
        httpd.serve_forever()
