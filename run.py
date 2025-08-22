from __future__ import annotations

from flask import Flask
from backend import db
import os

app = Flask(__name__)
app.config["SQLALCHEMY_DATABASE_URI"] = "sqlite:////data/data/com.termux/files/home/paste12/data/app.db"
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

db.init_app(app)

# Registrar blueprint DESPUÉS de init_app
from backend.routes import api as api_blueprint  # noqa: E402
app.register_blueprint(api_blueprint)

# Crear tablas
with app.app_context():
    db.create_all()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
