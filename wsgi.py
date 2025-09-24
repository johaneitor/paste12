# wsgi.py — punto de entrada para Gunicorn: wsgi:application
from backend import create_app  # type: ignore
application = create_app()
