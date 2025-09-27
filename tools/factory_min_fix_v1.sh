#!/usr/bin/env bash
set -euo pipefail

TS="$(date -u +%Y%m%d-%H%M%SZ)"

# --- 0) Backups seguros ---
mkdir -p tools/backups
[[ -f backend/__init__.py ]] && cp -f backend/__init__.py "tools/backups/__init__.py.$TS.bak" || true
[[ -f backend/routes.py ]]   && cp -f backend/routes.py   "tools/backups/routes.py.$TS.bak"   || true
[[ -f backend/routes_api_min.py ]] && cp -f backend/routes_api_min.py "tools/backups/routes_api_min.py.$TS.bak" || true
[[ -f wsgi.py ]] && cp -f wsgi.py "tools/backups/wsgi.py.$TS.bak" || true

# --- 1) routes_api_min.py: blueprint mínimo y correcto ---
mkdir -p backend
cat > backend/routes_api_min.py <<'PY'
from __future__ import annotations
from flask import Blueprint, jsonify, make_response, request

api_bp = Blueprint("api_bp", __name__)

@api_bp.route("/api/health", methods=["GET"])
def api_health():
    return jsonify(ok=True, api=True, ver="api-bp-min"), 200

@api_bp.route("/api/notes", methods=["OPTIONS"])
def api_notes_options():
    # 204 vacío con CORS canónico
    resp = make_response("", 204)
    h = resp.headers
    h["Access-Control-Allow-Origin"] = "*"
    h["Access-Control-Allow-Methods"] = "GET, POST, HEAD, OPTIONS"
    h["Access-Control-Allow-Headers"] = "Content-Type"
    h["Access-Control-Max-Age"] = "86400"
    return resp

@api_bp.route("/api/notes", methods=["GET"])
def api_notes_get():
    # Respuesta mínima saludable (si tu ORM aún no está listo)
    # Estructura amigable para el FE actual
    return jsonify(items=[], next=None), 200
PY

# --- 2) routes.py: si existe y tenía .options, lo normalizamos; si no existe, importamos el min ---
if [[ -f backend/routes.py ]]; then
  python - <<'PY'
import io,re
p="backend/routes.py"
s=io.open(p,"r",encoding="utf-8").read()
orig=s
# Reemplazar usos inválidos de .options por .route(..., methods=["OPTIONS"])
s=re.sub(r'(@\s*api_bp)\.options\s*\(',
         r'\\1.route(', s)
# Asegurar methods=["OPTIONS"] en esa ruta si no estuviera explícito
s=re.sub(r'(@\s*api_bp\.route\(\s*["\\\']/api/notes["\\\']\s*\))',
         r'\\1', s)
# Si la definición OPTIONS no declara methods, la agregamos:
s=re.sub(r'(@\s*api_bp\.route\(\s*["\\\']/api/notes["\\\']\s*\))\s*\\n',
         r'\\1, methods=["OPTIONS"]\\n', s)

if s!=orig:
    io.open(p,"w",encoding="utf-8").write(s)
    print("[routes] normalizado (.options -> .route(..., methods=[\"OPTIONS\"]))")
else:
    print("[routes] ya estaba OK o no fue necesario cambiar.")
PY
else
  # Creamos un routes.py que reexporte el min
  cat > backend/routes.py <<'PY'
from .routes_api_min import api_bp  # usa el blueprint mínimo
PY
  echo "[routes] creado (reexportando routes_api_min)"
fi

# --- 3) __init__.py: create_app estable + CORS canónico + registro de api_bp ---
cat > backend/__init__.py <<'PY'
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
PY

# --- 4) wsgi.py: exporta 'application' correcto ---
cat > wsgi.py <<'PY'
from backend import create_app  # type: ignore
application = create_app()
PY

# --- 5) sanity local ---
python -m py_compile backend/__init__.py wsgi.py
echo "[factory_min_fix] py_compile OK"

cat <<'MSG'
Listo. Ahora:
1) Commit & push (si corresponde).
2) En Render > Start Command (una sola línea, sin barras invertidas):
   gunicorn wsgi:application --chdir /opt/render/project/src -w ${WEB_CONCURRENCY:-2} -k gthread --threads ${THREADS:-4} --timeout ${TIMEOUT:-120} -b 0.0.0.0:$PORT
3) Redeploy.
MSG
