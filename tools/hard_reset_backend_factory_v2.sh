#!/usr/bin/env bash
set -euo pipefail

TS="$(date -u +%Y%m%d-%H%M%SZ)"

bak() { [[ -f "$1" ]] && cp -f "$1" "$1.$TS.bak" || true; }

mkdir -p backend

# --- backend/__init__.py (factory estable) ---
bak backend/__init__.py
cat > backend/__init__.py <<'PY'
from __future__ import annotations

import os
import logging
from typing import Optional, Dict, Any

from flask import Flask, jsonify
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()


def _normalize_db_url(url: str) -> str:
    if url.startswith("postgres://"):
        url = url.replace("postgres://", "postgresql+psycopg2://", 1)
    # Fuerza SSL (Render PG suele requerirlo); evita duplicar si ya viene
    if "sslmode=" not in url:
        url += ("&" if "?" in url else "?") + "sslmode=require"
    return url


def create_app(config_override: Optional[Dict[str, Any]] = None) -> Flask:
    app = Flask(__name__, static_folder=None)

    # --- Config DB obligatoria ---
    db_url = (config_override or {}).get("SQLALCHEMY_DATABASE_URI") or os.getenv("DATABASE_URL", "")
    if not db_url:
        # Evita que Gunicorn “arranque” sin DB y dé 500s opacos
        raise RuntimeError("DATABASE_URL no está definido (requerido).")

    app.config.update(
        SQLALCHEMY_DATABASE_URI=_normalize_db_url(db_url),
        SQLALCHEMY_TRACK_MODIFICATIONS=False,
        JSON_SORT_KEYS=False,
        # Motor: defensivo frente a cortes/SSL
        SQLALCHEMY_ENGINE_OPTIONS=dict(
            pool_pre_ping=True,
            pool_recycle=int(os.getenv("SQL_POOL_RECYCLE", "180")),
            pool_size=int(os.getenv("SQL_POOL_SIZE", "5")),
            max_overflow=int(os.getenv("SQL_MAX_OVERFLOW", "5")),
            pool_timeout=int(os.getenv("SQL_POOL_TIMEOUT", "30")),
        ),
    )

    # Extensiones
    db.init_app(app)
    CORS(app)  # CORS sencillo para /api/*

    # Health básico del factory (si fallan rutas, esto sigue vivo)
    @app.get("/api/health")
    def _health():
        return jsonify(ok=True, api=False, ver="factory-v6")

    # Registro de rutas API real, con fallback limpio
    try:
        from .routes import api_bp  # type: ignore
        app.register_blueprint(api_bp)
        # Re-declare /api/health indicando que estamos con API real:
        @app.get("/api/health")
        def _health_api():
            return jsonify(ok=True, api=True, ver="api-routes-v1")
    except Exception as e:
        logging.exception("[api] fallo registrando api_bp; habilitando fallback")
        err_text = str(e)

        @app.get("/api/notes")
        def _api_unavailable_notes():
            return jsonify(error="API routes not available", detail=err_text), 500

    # Raíz: no tocamos '/', lo sirve tu frontend/blueprint/estático actual
    return app
PY

# --- backend/routes.py (Blueprint sin ORM; SQL crudo para evitar circulares) ---
bak backend/routes.py
cat > backend/routes.py <<'PY'
from __future__ import annotations

from flask import Blueprint, current_app, jsonify, request, make_response
from sqlalchemy import text
from urllib.parse import urlencode

api_bp = Blueprint("api", __name__)


@api_bp.get("/api/health")
def health():
    # Si este handler existe, significa que el blueprint se registró OK
    return jsonify(ok=True, api=True, ver="api-routes-v1")


@api_bp.options("/api/notes")
def options_notes():
    # flask-cors se encarga de los headers; devolvemos 204 vacío
    return ("", 204)


@api_bp.get("/api/notes")
def get_notes():
    limit = request.args.get("limit", default=10, type=int)
    before_id = request.args.get("before_id", type=int)

    sql = "SELECT id, text, timestamp, expires_at, likes, views, reports, author_fp FROM notes"
    params = {}
    if before_id is not None:
        sql += " WHERE id < :before_id"
        params["before_id"] = before_id
    sql += " ORDER BY timestamp DESC LIMIT :limit"
    params["limit"] = max(1, min(limit, 50))

    dbi = current_app.extensions["sqlalchemy"].db
    rows = dbi.session.execute(text(sql), params).mappings().all()
    data = [dict(r) for r in rows]

    resp = make_response(jsonify(data))
    if data:
        last_id = data[-1]["id"]
        resp.headers["Link"] = f"<{request.base_url}?{urlencode({'limit': params['limit'], 'before_id': last_id})}>; rel=\"next\""
    return resp


@api_bp.post("/api/notes/<int:note_id>/like")
def like_note(note_id: int):
    dbi = current_app.extensions["sqlalchemy"].db
    row = dbi.session.execute(
        text("UPDATE notes SET likes=COALESCE(likes,0)+1 WHERE id=:id RETURNING id, likes"),
        {"id": note_id},
    ).first()
    dbi.session.commit()
    if not row:
        return jsonify(error="not found"), 404
    return jsonify(ok=True, id=row.id, likes=row.likes)
PY

# --- wsgi.py (exporta 'application') ---
bak wsgi.py
cat > wsgi.py <<'PY'
from backend import create_app  # type: ignore
application = create_app()
PY

# --- Validación sintáctica ---
python - <<'PY'
import py_compile, sys
for f in ("backend/__init__.py","backend/routes.py","wsgi.py"):
    try:
        py_compile.compile(f, doraise=True)
        print(f"[pyc] OK {f}")
    except py_compile.PyCompileError as e:
        print(f"[pyc] FAIL {f}: {e.msg}")
        sys.exit(1)
PY

echo "OK: backend factory + rutas reseteadas (backups con .$TS.bak)"
