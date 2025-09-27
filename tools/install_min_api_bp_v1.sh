#!/usr/bin/env bash
set -euo pipefail
mkdir -p backend
cat > backend/routes_api_min.py <<'PY'
from __future__ import annotations
from flask import Blueprint, jsonify, make_response, request

api_bp = Blueprint("api_bp_min", __name__)

@api_bp.route("/api/health", methods=["GET"])
def api_health():
    return jsonify(ok=True, api=True, ver="min-bp-v1")

@api_bp.route("/api/notes", methods=["GET"])
def notes_index():
    # Intentar DB si existe; devolver fallback vacío si falla
    try:
        from .models import Note  # type: ignore
        items = [{"id": n.id, "text": n.text, "likes": getattr(n, "likes", 0)} for n in Note.query.order_by(Note.id.desc()).limit(10)]
        resp = jsonify(items)
        resp.headers["Link"] = "</api/notes?limit=10>; rel=\"next\""
        return resp
    except Exception:
        resp = jsonify([])
        resp.headers["Link"] = "</api/notes?limit=10>; rel=\"next\""
        return resp, 200

@api_bp.route("/api/notes", methods=["OPTIONS"])
def notes_options():
    return _cors_preflight()

@api_bp.route("/api/<path:_rest>", methods=["OPTIONS"])
def any_options(_rest):
    return _cors_preflight()

def _cors_preflight():
    resp = make_response("", 204)
    h = resp.headers
    h["Access-Control-Allow-Origin"] = "*"
    h["Access-Control-Allow-Methods"] = "GET, POST, HEAD, OPTIONS"
    h["Access-Control-Allow-Headers"] = "Content-Type"
    h["Access-Control-Max-Age"] = "86400"
    return resp
PY
echo "[min-bp] backend/routes_api_min.py creado"

# Parchear backend/__init__.py para usar fallback + CORS + after_request
f="backend/__init__.py"
[ -f "$f" ] || { echo "[init] No existe $f"; exit 1; }
cp -f "$f" "$f.$(date -u +%Y%m%d-%H%M%SZ).minbp.bak"

python - <<'PY'
import re, pathlib
p = pathlib.Path("backend/__init__.py")
t = p.read_text(encoding="utf-8")

# Asegurar import de CORS
if "from flask_cors import CORS" not in t:
    t = t.replace("from flask import", "from flask import")  # no dup
    t = "from flask_cors import CORS\n" + t

# Inyectar dentro de create_app: CORS + registro api_bp (con fallback) + after_request
pat = r"(def\s+create_app\([^\)]*\)\s*:\s*\n)"
m = re.search(pat, t)
if not m:
    raise SystemExit("[init] No encontré def create_app(...)")

start = m.end()
# Buscar el `return app` más cercano (no perfecto pero práctico)
ret = re.search(r"\n\s*return\s+app\b", t[start:])
if not ret:
    raise SystemExit("[init] No encontré 'return app' dentro de create_app(...)")

ins = """
    # -- P12: CORS para /api/* --
    try:
        CORS(app, resources={r"/api/*": {"origins": "*"}}, supports_credentials=False)
    except Exception as _e:
        app.logger.warning("CORS not applied: %s", _e)

    # -- P12: registrar API blueprint con fallback --
    try:
        from .routes import api_bp as _api_bp  # type: ignore
    except Exception as e:
        app.logger.error("[api] usando fallback routes_api_min; error: %s", e)
        from .routes_api_min import api_bp as _api_bp  # type: ignore
    try:
        app.register_blueprint(_api_bp)
    except Exception as e:
        app.logger.error("[api] no pude registrar blueprint: %s", e)

    # -- P12: completar encabezados CORS en TODA respuesta /api/* --
    @app.after_request
    def _p12_after(resp):
        try:
            if getattr(resp, "headers", None) is not None:
                # Completamos siempre que la URL sea /api/...
                # (esto también aplica a errores 4xx/5xx)
                from flask import request as _rq  # lazy
                if _rq.path.startswith("/api/"):
                    H = resp.headers
                    H.setdefault("Access-Control-Allow-Origin", "*")
                    H.setdefault("Access-Control-Allow-Methods", "GET, POST, HEAD, OPTIONS")
                    H.setdefault("Access-Control-Allow-Headers", "Content-Type")
                    H.setdefault("Access-Control-Max-Age", "86400")
        except Exception:
            pass
        return resp
"""

block = t[start:start+ret.start()] + ins + t[start+ret.start():]
t = t[:start] + block

p.write_text(t, encoding="utf-8")
print("[init] create_app parcheado con CORS+fallback+after_request")
PY

python -m py_compile backend/__init__.py backend/routes_api_min.py || { echo "py_compile FAIL"; exit 1; }
echo "[min-bp] py_compile OK"
