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
