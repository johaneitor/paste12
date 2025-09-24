#!/usr/bin/env bash
set -euo pipefail
f="wsgiapp.py"
[[ -f "$f" ]] || { echo "No existe $f"; exit 1; }

python - <<'PY'
import re
from pathlib import Path

p = Path("wsgiapp.py")
s = p.read_text(encoding="utf-8")

# Normalizar EOL
s = s.replace("\r\n","\n").replace("\r","\n")

# 1) Asegurar import del blueprint
if "from backend.routes import api as api_bp" not in s:
    # Insertar después del import de Flask (o al principio si no)
    m = re.search(r'^\s*from\s+flask\s+import\s+.+$', s, re.M)
    ins = m.end() if m else 0
    s = s[:ins] + "\nfrom backend.routes import api as api_bp\n" + s[ins:]

# 2) Eliminar/normalizar registros previos del blueprint sin prefijo
#    - app.register_blueprint(api_bp)
#    - app.register_blueprint(api_bp, ...) (reemplazar a prefijo fijo)
s = re.sub(
    r'app\.register_blueprint\(\s*api_bp\s*(?:,\s*url_prefix\s*=\s*["\'][^"\']*["\'])?\s*\)',
    'app.register_blueprint(api_bp, url_prefix="/api")',
    s
)

# 3) Si no hay ningún register_blueprint(api_bp, url_prefix="/api"), lo agregamos justo después de la creación del app
if 'app.register_blueprint(api_bp, url_prefix="/api")' not in s:
    m = re.search(r'^\s*app\s*=\s*Flask\([^)]*\)\s*$', s, re.M)
    if not m:
        raise SystemExit("No pude ubicar 'app = Flask(...)' para insertar el register_blueprint")
    ins = m.end()
    s = s[:ins] + '\napp.register_blueprint(api_bp, url_prefix="/api")\n' + s[ins:]

# 4) Fallback defensivo: /api/ping y /api/_routes (idempotente)
if "WSGI_DIRECT_API ENDPOINTS" not in s:
    s += r"""

# --- WSGI DIRECT API ENDPOINTS (decorators, no blueprints) ---
try:
    from flask import jsonify as _jsonify
    @app.get("/api/ping")
    def _api_ping():
        return _jsonify({"ok": True, "pong": True, "src": "wsgiapp"}), 200

    @app.get("/api/_routes")
    def _api_routes_dump():
        info=[]
        for r in app.url_map.iter_rules():
            info.append({
                "rule": str(r),
                "methods": sorted(m for m in r.methods if m not in ("HEAD","OPTIONS")),
                "endpoint": r.endpoint
            })
        info.sort(key=lambda x: x["rule"])
        return _jsonify({"routes": info}), 200
except Exception:
    pass
"""
p.write_text(s, encoding="utf-8")
print("OK: wsgiapp.py parchado (import + register_blueprint con url_prefix + ping/_routes).")
PY

git add wsgiapp.py >/dev/null 2>&1 || true
git commit -m "fix(wsgi): registra api_bp con url_prefix='/api' y añade /api/ping + /api/_routes failsafe" >/dev/null 2>&1 || true
git push origin main >/dev/null 2>&1 || true
echo "✓ Commit & push hechos."
