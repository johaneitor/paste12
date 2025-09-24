from __future__ import annotations
import os, re
from flask import Flask, jsonify, send_from_directory
from flask_sqlalchemy import SQLAlchemy
from flask_cors import CORS

db = SQLAlchemy()

def _normalize_db_url(url: str) -> str:
    if not url: return url
    # postgres -> postgresql+psycopg2 (soporta Render)
    url = re.sub(r'^postgres(?=://)', 'postgresql+psycopg2', url)
    return url

def create_app() -> Flask:
    app = Flask(__name__, static_folder="../frontend", static_url_path="")
    # Config DB
    db_url = _normalize_db_url(os.environ.get("DATABASE_URL", ""))
    if db_url:
        app.config["SQLALCHEMY_DATABASE_URI"] = db_url
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

    # CORS abierto (como vienes testeando)
    CORS(app, resources={r"/api/*": {"origins": "*"}}, supports_credentials=False)

    # Inicializar DB
    db.init_app(app)

    # Registrar blueprint API
    from .routes import bp as api_bp
    app.register_blueprint(api_bp)

    # Health minimal sin DB
    @app.route("/api/health")
    def health():
        return jsonify({"ok": True, "api": True, "ver": "factory-v1"})

    # Servir el frontend (index.html) y estáticos
    @app.route("/")
    def index():
        return send_from_directory(app.static_folder, "index.html")

    return app

# Export para gunicorn
app = create_app()
