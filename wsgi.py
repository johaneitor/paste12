# Punto único de entrada para gunicorn: wsgi:app
# Mantenerlo mínimo para evitar dobles registros.
from backend.entry import app  # noqa: F401
