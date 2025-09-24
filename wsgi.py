from __future__ import annotations
try:
    # Si el módulo ya expone app, úsalo
    from backend import app as application  # type: ignore
except Exception:
    # Fallback a create_app
    from backend import create_app  # type: ignore
    application = create_app()
