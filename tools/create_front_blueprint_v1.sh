#!/usr/bin/env bash
set -euo pipefail
mkdir -p backend frontend

# No pisamos tus HTML si ya existen
[[ -f frontend/index.html ]] || echo "<!doctype html><meta charset=utf-8><title>Paste12</title><h1>Paste12</h1><div class='views'>0</div>" > frontend/index.html
[[ -f frontend/terms.html ]] || echo "<!doctype html><meta charset=utf-8><title>Términos</title><h1>Términos</h1>" > frontend/terms.html
[[ -f frontend/privacy.html ]] || echo "<!doctype html><meta charset=utf-8><title>Privacidad</title><h1>Privacidad</h1>" > frontend/privacy.html

cat > backend/front_serve.py <<'PY'
from __future__ import annotations
import os
from flask import Blueprint, send_from_directory, make_response, current_app

front_bp = Blueprint("front_bp", __name__)

ROOT = os.path.dirname(os.path.dirname(__file__))
FE_DIR = os.path.join(ROOT, "frontend")

def _serve(name: str):
    resp = make_response(send_from_directory(FE_DIR, name))
    # Evitar caché pegada entre versiones
    resp.headers["Cache-Control"] = "no-store, max-age=0"
    return resp

@front_bp.route("/")
def index():
    return _serve("index.html")

@front_bp.route("/terms")
def terms():
    return _serve("terms.html")

@front_bp.route("/privacy")
def privacy():
    return _serve("privacy.html")
PY

python -m py_compile backend/front_serve.py
echo "[front_bp] listo"
