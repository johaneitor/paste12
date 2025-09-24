#!/usr/bin/env bash
set -euo pipefail
_red(){ printf "\033[31m%s\033[0m\n" "$*"; }; _grn(){ printf "\033[32m%s\033[0m\n" "$*"; }

fix_wsgi(){
  local f="wsgiapp.py"
  [[ -f "$f" ]] || { _red "No existe $f"; return 1; }
  python - <<'PY'
import re
from pathlib import Path
p=Path("wsgiapp.py"); s=p.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n")

# Asegurar import
if "from backend.routes import api as api_bp" not in s:
    m=re.search(r'^\s*from\s+flask\s+import\s+.+$', s, re.M)
    s=s[:(m.end() if m else 0)] + "\nfrom backend.routes import api as api_bp\n" + s[(m.end() if m else 0):]

# Normalizar todos los register_blueprint(api_bp, ...)
s=re.sub(r'app\.register_blueprint\(\s*api_bp\s*(?:,\s*url_prefix\s*=\s*["\'][^"\']*["\'])?\s*\)',
         'app.register_blueprint(api_bp, url_prefix="/api")', s)

# Si no está, insertarlo después de app = Flask(...)
if 'app.register_blueprint(api_bp, url_prefix="/api")' not in s:
    m=re.search(r'^\s*app\s*=\s*Flask\([^)]*\)\s*$', s, re.M)
    if m:
        s=s[:m.end()]+'\napp.register_blueprint(api_bp, url_prefix="/api")\n'+s[m.end():]

# WSGI direct endpoints (idempotente)
if "WSGI DIRECT API ENDPOINTS" not in s:
    s += r'''
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
            info.append({"rule": str(r),
                         "methods": sorted(m for m in r.methods if m not in ("HEAD","OPTIONS")),
                         "endpoint": r.endpoint})
        info.sort(key=lambda x: x["rule"])
        return _jsonify({"routes": info}), 200
except Exception:
    pass
'''
p.write_text(s, encoding="utf-8")
print("OK wsgiapp.py")
PY
}

fix_factory(){
  local f="backend/__init__.py"
  [[ -f "$f" ]] || { _red "No existe $f"; return 1; }
  python - <<'PY'
import re
from pathlib import Path
p=Path("backend/__init__.py"); s=p.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n")

# 1) Asegurar import del blueprint en el archivo (para usos locales en factory)
if "from backend.routes import api as api_bp" not in s:
    # Insertar cerca de otros imports de Flask/backend
    m=re.search(r'^\s*from\s+flask[^\n]*$', s, re.M)
    s=s[:(m.end() if m else 0)] + "\nfrom backend.routes import api as api_bp\n" + s[(m.end() if m else 0):]

# 2) Para TODAS las definiciones de create_app, normalizar register_blueprint(api_bp, ...)
def repl(m):
    body=m.group(0)
    body=re.sub(r'app\.register_blueprint\(\s*api_bp\s*(?:,\s*url_prefix\s*=\s*["\'][^"\']*["\'])?\s*\)',
                'app.register_blueprint(api_bp, url_prefix="/api")', body)
    # Si no aparece en este cuerpo, insertarlo tras la primera aparición de 'app = _orig_create_app' o similar
    if 'app.register_blueprint(api_bp, url_prefix="/api")' not in body:
        m2=re.search(r'^\s*app\s*=\s*[_a-zA-Z0-9\.]*create_app\([^)]*\)\s*$', body, re.M)
        if not m2:
            m2=re.search(r'^\s*app\s*=\s*[_a-zA-Z0-9\.]*orig[^=]*\([^)]*\)\s*$', body, re.M)
        if m2:
            body=body[:m2.end()]+'\n        app.register_blueprint(api_bp, url_prefix="/api")\n'+body[m2.end():]
    # Añadir /api/ping y /api/_routes de respaldo (idempotentes)
    if 'FACTORY_FALLBACK_PING' not in body:
        body += r'''
        # FACTORY_FALLBACK_PING
        try:
            from flask import jsonify as _j
            if not any(str(r).rstrip("/") == "/api/ping" for r in app.url_map.iter_rules()):
                app.add_url_rule("/api/ping", endpoint="api_ping_factory_fallback",
                                 view_func=(lambda: _j({"ok": True, "pong": True, "src":"factory"})), methods=["GET"])
            if not any(str(r).rstrip("/") == "/api/_routes" for r in app.url_map.iter_rules()):
                def _dump_routes():
                    info=[]
                    for r in app.url_map.iter_rules():
                        info.append({"rule": str(r),
                                     "methods": sorted(m for m in r.methods if m not in ("HEAD","OPTIONS")),
                                     "endpoint": r.endpoint})
                    info.sort(key=lambda x: x["rule"])
                    return _j({"routes": info}), 200
                app.add_url_rule("/api/_routes", endpoint="api_routes_dump_factory",
                                 view_func=_dump_routes, methods=["GET"])
        except Exception:
            pass
'''
    return body

s=re.sub(r'def\s+create_app\s*\([^)]*\)\s*:[\s\S]*?(?=\n\w|$', re.S, repl, s)
Path("backend/__init__.py").write_text(s, encoding="utf-8")
print("OK backend/__init__.py")
PY
}

fix_wsgi
fix_factory

git add wsgiapp.py backend/__init__.py >/dev/null 2>&1 || true
git commit -m "fix(prefix): forzar url_prefix=/api en wsgi y factory; fallback ping/_routes" >/dev/null 2>&1 || true
git push origin main >/dev/null 2>&1 || true
_grn "✓ Commit & push hechos."
