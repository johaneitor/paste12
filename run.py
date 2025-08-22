from __future__ import annotations

import os, re, pathlib
from flask import Flask
from backend import db

def _db_uri() -> str:
    uri = os.getenv("DATABASE_URL")
    if uri:
        # postgres -> postgresql+psycopg
        uri = re.sub(r'^postgres://', 'postgresql+psycopg://', uri)
        # postgresql:// -> postgresql+psycopg:// si no trae driver
        if uri.startswith('postgresql://') and '+psycopg://' not in uri:
            uri = uri.replace('postgresql://', 'postgresql+psycopg://', 1)
        return uri
    # Fallback SQLite local
    db_path = pathlib.Path('data/app.db').resolve()
    return f"sqlite:///{db_path}"

app = Flask(__name__)
app.config["SQLALCHEMY_DATABASE_URI"] = _db_uri()
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {
    "pool_pre_ping": True,
    "pool_recycle": 280,
}

db.init_app(app)

from backend.routes import api as api_blueprint  # noqa: E402
app.register_blueprint(api_blueprint)

with app.app_context():
    # create_all para entornos sin migraciones; en Postgres no hace daño si ya existen
    db.create_all()

if __name__ == "__main__":
    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", "8000"))
    app.run(host=host, port=port)
