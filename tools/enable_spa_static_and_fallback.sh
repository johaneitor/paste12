#!/usr/bin/env bash
set -Eeuo pipefail
FILE="backend/__init__.py"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
LOG="$PREFIX/tmp/paste12_server.log"

echo "➤ Backup"
cp -f "$FILE" "$FILE.bak.$(date +%s)" 2>/dev/null || true

echo "➤ Escribiendo backend/__init__.py con estáticos + SPA fallback"
cat > "$FILE" <<'PY'
from __future__ import annotations

import os, re, pathlib
from flask import Flask, send_from_directory, abort
from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()

def _db_uri() -> str:
    uri = os.getenv("DATABASE_URL")
    if uri:
        # postgres -> postgresql+psycopg
        uri = re.sub(r"^postgres://", "postgresql+psycopg://", uri)
        # postgresql:// -> postgresql+psycopg:// si falta el driver
        if uri.startswith("postgresql://") and "+psycopg://" not in uri:
            uri = uri.replace("postgresql://", "postgresql+psycopg://", 1)
        return uri
    # Fallback SQLite local
    db_path = pathlib.Path("data/app.db").resolve()
    return f"sqlite:///{db_path}"

def _detect_static_folder() -> tuple[str | None, str]:
    """
    Busca una carpeta de estáticos en el repo con un index.html.
    Orden de preferencia: frontend/, public/, static/, dist/, build/
    Devuelve (ruta_absoluta_o_None, nombre_detectado)
    """
    root = pathlib.Path(__file__).resolve().parent.parent  # raíz del proyecto
    candidates = ["frontend", "public", "static", "dist", "build"]
    for name in candidates:
        p = root / name
        if p.is_dir():
            idx = p / "index.html"
            if idx.exists():
                return (str(p), name)
    return (None, "")

def create_app():
    static_folder, static_name = _detect_static_folder()
    if static_folder:
        app = Flask(__name__, static_folder=static_folder, static_url_path="")
    else:
        app = Flask(__name__)

    app.config["SQLALCHEMY_DATABASE_URI"] = _db_uri()
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {
        "pool_pre_ping": True,
        "pool_recycle": 280,
    }

    db.init_app(app)

    # Registrar API blueprint después de init_app
    from .routes import api as api_blueprint  # import diferido
    app.register_blueprint(api_blueprint)

    # Crear tablas si no existen
    with app.app_context():
        db.create_all()

    # ---- Rutas estáticas / SPA fallback (si tenemos static_folder) ----
    if static_folder:
        rules = {r.rule for r in app.url_map.iter_rules()}

        if "/" not in rules:
            def _root():
                idx = os.path.join(app.static_folder, "index.html")
                if os.path.exists(idx):
                    return send_from_directory(app.static_folder, "index.html")
                return "", 200
            app.add_url_rule("/", endpoint="static_root", view_func=_root)

        if "static_any" not in app.view_functions:
            def static_any(path: str):
                # No interceptar la API
                if path.startswith("api/"):
                    return abort(404)
                full = os.path.join(app.static_folder, path)
                # Si el archivo existe, lo servimos tal cual
                if os.path.isfile(full):
                    return send_from_directory(app.static_folder, path)
                # Fallback SPA: devolver index.html
                idx = os.path.join(app.static_folder, "index.html")
                if os.path.exists(idx):
                    return send_from_directory(app.static_folder, "index.html")
                return abort(404)
            app.add_url_rule("/<path:path>", endpoint="static_any", view_func=static_any)

    # Exponer qué carpeta se detectó (útil para logs)
    app.logger.info("static_folder=%s", static_name or "none")
    return app
PY

echo "➤ Validando sintaxis"
python -m py_compile backend/__init__.py

echo "➤ Reinicio local"
pkill -f "python .*run\.py" 2>/dev/null || true
sleep 1
nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 2

echo "➤ Smokes locales"
echo "health=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/api/health)"
echo "root=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/)"
echo "password=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/password)"

echo "➤ Commit & push"
git add backend/__init__.py
git commit -m "feat(static): servir SPA con fallback a index.html; no interceptar /api/*; auto-detección de carpeta de estáticos"
git push origin main || true

echo "Log: $LOG  (tail -n 120 \"$LOG\")"
