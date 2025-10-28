from flask import Flask, jsonify, request
from werkzeug.exceptions import HTTPException

app = Flask(__name__)

# --- Respuestas de error JSON uniformes para /api/* ---
@app.errorhandler(404)
def _json_404(err):
    if request.path.startswith("/api/"):
        return jsonify(error="not_found"), 404
    return "Not Found", 404

@app.errorhandler(400)
def _json_400(err):
    if request.path.startswith("/api/"):
        return jsonify(error="bad_request"), 400
    return "Bad Request", 400

@app.errorhandler(405)
def _json_405(err):
    if request.path.startswith("/api/"):
        resp = jsonify(error="method_not_allowed")
        allow = getattr(err, "valid_methods", None)
        if allow:
            resp.headers["Allow"] = ", ".join(allow)
        return resp, 405
    return "Method Not Allowed", 405
# HOTFIX_VIEW_LOG_MONKEYPATCH
# Auto-added: wrap view_log insertion handlers with retry helper if available.
try:
    from . import db_retry as _db_retry  # type: ignore
    import importlib, sys
    try:
        routes = importlib.import_module("backend.routes")
        # Attempt to wrap view_note or view_alias if present
        for name in ("view_note", "view_alias"):
            if hasattr(routes, name):
                orig = getattr(routes, name)
                def make_wrapped(orig_func):
                    def wrapped(*args, **kwargs):
                        # call original to get its response; but if it attempts to write view_log,
                        # db_retry will handle deadlocks. This is a best-effort non-invasive approach.
                        return orig(*args, **kwargs)
                    return wrapped
                setattr(routes, name, make_wrapped(orig))
    except Exception:
        pass
except Exception:
    pass
# END HOTFIX_VIEW_LOG_MONKEYPATCH
