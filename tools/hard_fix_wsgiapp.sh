#!/usr/bin/env bash
set -euo pipefail

py_edit() {
python - "$@" <<'PY'
from pathlib import Path, re
path = Path("wsgiapp.py")
s = path.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n")

changed = False

# 1) Importar failsafe si falta
if "from backend.force_api import install as _force_api_install" not in s:
    # inserta el import debajo del primer "from backend import"
    s = re.sub(r'(from\s+backend\s+import\s+create_app[^\n]*\n)',
               r'\1from backend.force_api import install as _force_api_install\n',
               s, count=1)
    changed = True

# 2) Asegurar url_prefix="/api" al registrar blueprint
s = re.sub(r'(app\.register_blueprint\s*\(\s*api_bp\s*\))',
           r'app.register_blueprint(api_bp, url_prefix="/api")', s)
if s != path.read_text(encoding="utf-8"):
    changed = True

# 3) Añadir ping/_routes a nivel app si faltan (failsafe local en wsgi)
if "WSGI_LOCAL_PING_ROUTES" not in s:
    s += '''

# --- WSGI_LOCAL_PING_ROUTES (idempotente) ---
try:
    from flask import jsonify as _j
    def _dump_routes_app(app):
        info=[]
        for r in app.url_map.iter_rules():
            info.append({"rule": str(r),
                         "methods": sorted(m for m in r.methods if m not in ("HEAD","OPTIONS")),
                         "endpoint": r.endpoint})
        info.sort(key=lambda x: x["rule"])
        return _j({"routes": info}), 200
    if not any(str(r).rstrip("/") == "/api/ping" for r in app.url_map.iter_rules()):
        app.add_url_rule("/api/ping", endpoint="api_ping_wsgi_local",
                         view_func=(lambda: _j({"ok": True, "pong": True, "src": "wsgi-local"})),
                         methods=["GET"])
    if not any(str(r).rstrip("/") == "/api/_routes" for r in app.url_map.iter_rules()):
        app.add_url_rule("/api/_routes", endpoint="api_routes_dump_wsgi_local",
                         view_func=(lambda: _dump_routes_app(app)), methods=["GET"])
except Exception:
    pass
'''
    changed = True

# 4) Llamar al failsafe (si no está)
if "_force_api_install(app)" not in s:
    s = re.sub(r'(app\s*=\s*create_app\(\)\s*)',
               r'\1\n_force_api_install(app)\n',
               s, count=1)
    changed = True

if changed:
    path.write_text(s, encoding="utf-8")
    print("patched wsgiapp.py")
else:
    print("no changes needed in wsgiapp.py")
PY
}

# Ejecutar edición
py_edit

# Commit & push
git add wsgiapp.py >/dev/null 2>&1 || true
git commit -m "hotfix(wsgi): url_prefix=/api, import & call failsafe, add local /api/ping and /api/_routes" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true

echo "✓ Commit & push hechos."
echo "Ahora valida:"
echo "  tools/smoke_ping_diag.sh \"\${1:-https://paste12-rmsk.onrender.com}\""
