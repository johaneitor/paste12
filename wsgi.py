# -*- coding: utf-8 -*-
# WSGI entrypoint: reexporta 'application' desde el shim
try:
    from contract_shim import application  # noqa: F401
except Exception as e:
    # Fallback minimal para no romper healthcheck si el shim falla
    from flask import Flask, jsonify
    _app = Flask(__name__)
    @_app.get("/api/health")
    def _health():
        return jsonify(ok=True, api=False, diag=str(e), ver="wsgi-export-fallback")
    application = _app
