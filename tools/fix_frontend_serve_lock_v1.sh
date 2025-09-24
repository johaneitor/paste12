#!/usr/bin/env bash
set -euo pipefail

TS="$(date -u +%Y%m%d-%H%M%SZ)"

[[ -f backend/__init__.py ]] || { echo "ERROR: falta backend/__init__.py"; exit 2; }
mkdir -p backend

# 1) Crear/actualizar módulo que agrega rutas frontend leídas del repo
cat > backend/front_serve.py <<'PY'
import os
from flask import Response, Blueprint, send_from_directory, current_app

_bp = Blueprint("p12_front", __name__)
_FRONT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "frontend"))

def _html_resp(path, add_signature=True):
    full = os.path.join(_FRONT_DIR, path)
    with open(full, "rb") as f:
        body = f.read()
    resp = Response(body, mimetype="text/html; charset=utf-8")
    # Candado anti-caché y firma de origen
    resp.headers["Cache-Control"] = "no-store, max-age=0"
    if add_signature:
        resp.headers["X-Frontend-Src"] = f"repo:{os.path.relpath(full)}"
    # (Opcional) pista para que cualquier middleware de inyección lo saltee
    resp.headers["X-Skip-Hotfix"] = "1"
    return resp

@_bp.route("/")
def index():
    # Servir EXACTO el index del repo
    return _html_resp("index.html")

@_bp.route("/terms")
def terms():
    return _html_resp("terms.html")

@_bp.route("/privacy")
def privacy():
    return _html_resp("privacy.html")

def init_front_routes(app):
    # Registrar blueprint raíz SIN prefijo
    app.register_blueprint(_bp)
PY

# 2) Parchear create_app() para llamar init_front_routes(app)
cp -f backend/__init__.py "backend/__init__.py.${TS}.bak"

python - <<'PY'
import io, re, sys
p="backend/__init__.py"
s=io.open(p,"r",encoding="utf-8").read()
orig=s
# Asegurar import
if "from .front_serve import init_front_routes" not in s:
    # insertar import cerca de otros imports del backend
    s=re.sub(r'(\nfrom\s+\.?\s*\w+\s+import[^\n]*\n|[\s\S]*?)(?=from|import|class|def)',
             r'\1from .front_serve import init_front_routes\n', s, count=1)

# Insertar llamada dentro de create_app(app) después de crear app
# Buscamos el final de create_app y metemos la llamada antes del return
pat=r'(def\s+create_app\s*\([^\)]*\)\s*:\s*[\s\S]*?\n\s*return\s+app)'
m=re.search(pat, s)
if not m:
    print("ERROR: no encontré create_app(...) en backend/__init__.py", file=sys.stderr)
    sys.exit(3)

block=m.group(1)
if "init_front_routes(app)" not in block:
    block=block.replace("\n    return app",
                        "\n    # Candado: servir frontend directamente desde repo\n"
                        "    init_front_routes(app)\n"
                        "    return app")
    s=s[:m.start(1)]+block+s[m.end(1):]

if s!=orig:
    io.open(p,"w",encoding="utf-8").write(s)
    print("[front-lock] backend/__init__.py actualizado")
else:
    print("[front-lock] backend/__init__.py ya tenía el candado")

PY

# 3) Compilar
python -m py_compile backend/front_serve.py backend/__init__.py || { echo "py_compile FAIL"; exit 4; }

echo "Listo. Despliega y probamos."
