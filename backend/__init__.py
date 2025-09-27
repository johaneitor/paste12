from __future__ import annotations

from flask import Flask, jsonify
try:
    from flask_cors import CORS
except Exception:  # si falta, el app igual arranca
    CORS = None  # type: ignore

def create_app() -> "Flask":
    app = Flask(__name__, static_folder=None)

    # CORS canónico en /api/*
    if CORS:
        CORS(app, resources={r"/api/*": {"origins": "*"}}, supports_credentials=False)

    # Registrar API blueprint
    try:
        from .routes import api_bp  # type: ignore
        app.register_blueprint(api_bp)
        app.logger.info("[factory] api_bp registrado.")
    except Exception as e:
        app.logger.exception("[factory] fallo registrando api_bp, usando fallback mínimo.")
        # Endpoints de contingencia
        @app.route("/api/health", methods=["GET"])
        def _health_fallback():
            return jsonify(ok=True, api=False, ver="factory-fallback", detail=str(e)), 200

        @app.route("/api/notes", methods=["GET","OPTIONS"])
        def _notes_fallback():
            return jsonify(error="API routes not loaded", detail=str(e)), 500

    # Raíz: si el FE se sirve por CDN/estático de Render, mantener 200 para HEAD/GET
    @app.route("/", methods=["HEAD","GET"])
    def _root_ok():
        # No servimos index aquí para no interferir con front/CDN;
        # devolvemos 200 para health interna de Render/monitoring.
        return ("", 200)

    return app
