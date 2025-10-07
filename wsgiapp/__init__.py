from __future__ import annotations

"""WSGI shim (inert).

Delegates to backend.create_app() so there is a single
source of truth for all API and frontend endpoints.
No routes are defined here.
"""

from backend import create_app

# Build the real app from backend factory
app = create_app()

# Export for gunicorn compatibility if someone uses `wsgiapp:app`
application = app
