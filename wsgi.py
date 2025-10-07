from __future__ import annotations

"""Minimal WSGI entrypoint for Gunicorn.

Exports `application` compatible with `gunicorn wsgi:application`.
"""

from backend import create_app

application = create_app()
