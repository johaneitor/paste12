#!/usr/bin/env bash
set -euo pipefail

P="backend/__init__.py"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
[[ -f "$P" ]] || { echo "ERROR: falta $P"; exit 1; }

cp -f "$P" "$P.$TS.bak"
echo "[fix] Backup: $P.$TS.bak"

python - <<'PY'
import io, re, sys, pathlib
p = pathlib.Path("backend/__init__.py")
s = p.read_text(encoding="utf-8")
orig = s

# 1) Importaciones necesarias (idempotente)
def ensure_import(s, mod, names):
    block = f"from {mod} import {', '.join(names)}"
    if re.search(rf'from\s+{re.escape(mod)}\s+import\b.*\b{re.escape(names[0])}\b', s):
        return s
    return block + "\n" + s

s = ensure_import(s, "flask", ["Flask","jsonify","send_file","current_app"])
s = ensure_import(s, "pathlib", ["Path"])
if "CORS(" not in s:
    # CORS es requerido por varios flujos; si ya está importado, no duplicar
    if "from flask_cors import CORS" not in s:
        s = "from flask_cors import CORS\n" + s

# 2) Helpers para localizar frontend
helpers = r"""
# === auto: helpers frontend ===
def _frontend_dir() -> Path:
    return Path(__file__).resolve().parent.parent / "frontend"

def _send_html_file(path: Path):
    if path.exists():
        resp = send_file(str(path), mimetype="text/html")
        resp.headers["Cache-Control"] = "no-store"
        return resp
    # mini fallback
    html = (
        "<!doctype html><meta charset='utf-8'>"
        "<title>Paste12</title>"
        "<h1>Paste12</h1><p>Frontend base no encontrado.</p>"
    )
    return (html, 200, {"Content-Type":"text/html; charset=utf-8","Cache-Control":"no-store"})
"""

if "def _frontend_dir()" not in s:
    s = s + "\n" + helpers + "\n"

# 3) Registrar rutas front si faltan
front_routes = r"""
# === auto: front routes (/, /terms, /privacy) ===
def register_front_routes(app: Flask) -> None:
    @app.get("/")
    def index():
        return _send_html_file(_frontend_dir() / "index.html")

    @app.get("/terms")
    def terms():
        return _send_html_file(_frontend_dir() / "terms.html")

    @app.get("/privacy")
    def privacy():
        return _send_html_file(_frontend_dir() / "privacy.html")
"""

if "def register_front_routes(app" not in s:
    s = s + "\n" + front_routes + "\n"

# 4) Fallback de API seguro (no usar variable 'e' inexistente)
api_fallback = r"""
# === auto: api fallback ===
def register_api_fallback(app: Flask) -> None:
    @app.route("/api/<path:_rest>", methods=["GET","POST","HEAD","OPTIONS"])
    def _api_unavailable(_rest):
        # No referenciar 'e' inexistente aquí
        return jsonify(error="api_unavailable", path=_rest), 500
"""

if "def register_api_fallback(app" not in s:
    s = s + "\n" + api_fallback + "\n"

# 5) Inyectar registro dentro de create_app() antes de 'return app'
m = re.search(r'def\s+create_app\s*\([^)]*\)\s*:\s*(.*?)\n\s*return\s+app\b', s, flags=re.S)
if m:
    body = m.group(1)
    # Ya registra?
    need_front = "register_front_routes(app)" not in body
    need_api   = "register_api_fallback(app)" not in body
    inject = ""
    if need_front:
        inject += "\n    try:\n        register_front_routes(app)\n    except Exception as _e:\n        current_app.logger.warning('front routes skipped: %s', _e)\n"
    if need_api:
        inject += "\n    try:\n        register_api_fallback(app)\n    except Exception as _e:\n        current_app.logger.warning('api fallback skipped: %s', _e)\n"
    if inject:
        new = re.sub(r'(\n\s*return\s+app\b)', inject + r'\1', s, count=1, flags=re.S)
        s = new

# 6) Limpiar fallos previos de _api_unavailable con 'e'
s = re.sub(
    r'def\s+_api_unavailable\s*\(\s*\)\s*:\s*return\s+jsonify\(.*?e.*?\)',
    'def _api_unavailable():\n    return jsonify(error="api_unavailable"), 500',
    s, flags=re.S
)

if s != orig:
    p.write_text(s, encoding="utf-8")
    print("[fix] backend/__init__.py actualizado")
else:
    print("[fix] No hubo cambios (ya estaba OK)")
PY

python -m py_compile backend/__init__.py && echo "[fix] py_compile OK" || { echo "py_compile FAIL"; exit 2; }

echo "Listo. Aplica rutas front + fallback API. Despliega y probamos."
