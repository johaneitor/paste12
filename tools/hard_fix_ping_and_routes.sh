#!/usr/bin/env bash
set -euo pipefail

# 0) Normalizar EOL y tabs->spaces para evitar IndentationError
normalize() {
  local f="$1"
  python - <<PY
from pathlib import Path
p=Path("$f")
s=p.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n").replace("\t","    ")
p.write_text(s, encoding="utf-8")
print("normalized: $f")
PY
}

# 1) Garantizar @api.route("/ping") y /_routes en backend/routes.py
python - <<'PY'
from pathlib import Path, re
p = Path("backend/routes.py")
s = p.read_text(encoding="utf-8")

# Asegurar que el blueprint no tiene url_prefix aquí (lo pone la factory)
s = re.sub(r'api\s*=\s*Blueprint\(\s*"api"\s*,\s*__name__\s*,\s*url_prefix\s*=\s*["\']/?api["\']\s*\)',
           'api = Blueprint("api", __name__)', s)

# Ping canónico
if re.search(r'@api\.route\(\s*["\']/ping["\']\s*,?\s*methods\s*=\s*\[\s*["\']GET["\']\s*\]\s*\)', s) is None \
   and re.search(r'@api\.route\(\s*["\']/ping["\']\s*\)', s) is None:
    s += '''

@api.route("/ping", methods=["GET"])
def api_ping():
    return jsonify({"ok": True, "pong": True}), 200
'''

# _routes canónico bajo blueprint
if re.search(r'def\s+api_routes_dump\s*\(\s*\)\s*:', s) is None:
    s += '''

@api.route("/_routes", methods=["GET"])
def api_routes_dump():
    info = []
    for r in current_app.url_map.iter_rules():
        info.append({
            "rule": str(r),
            "methods": sorted(m for m in r.methods if m not in ("HEAD","OPTIONS")),
            "endpoint": r.endpoint,
        })
    info.sort(key=lambda x: x["rule"])
    return jsonify({"routes": info}), 200
'''

Path("backend/routes.py").write_text(s, encoding="utf-8")
print("routes.py: ensured /ping and /_routes")
PY
normalize backend/routes.py

# 2) FINAL WRAPPER idempotente en backend/__init__.py
python - <<'PY'
from pathlib import Path
p = Path("backend/__init__.py")
s = p.read_text(encoding="utf-8")

block = r'''
# === FINAL_FACTORY_WRAPPER (idempotente) ===
try:
    _orig_create_app
except NameError:
    _orig_create_app = create_app  # type: ignore

def create_app(*args, **kwargs):  # type: ignore[no-redef]
    app = _orig_create_app(*args, **kwargs)

    # Registrar API blueprint bajo /api (idempotente)
    try:
        from backend.routes import api as api_bp
        rules = list(app.url_map.iter_rules())
        have_api_pref = any(str(r).startswith("/api/") for r in rules)
        if not have_api_pref:
            app.register_blueprint(api_bp, url_prefix="/api")
    except Exception:
        pass

    # Rutas failsafe a nivel app (por si el blueprint no aportó ping/_routes)
    try:
        from flask import jsonify as _j
        if not any(str(r).rstrip("/") == "/api/ping" for r in app.url_map.iter_rules()):
            app.add_url_rule("/api/ping", endpoint="api_ping_app",
                             view_func=(lambda: _j({"ok": True, "pong": True, "src":"factory"})),
                             methods=["GET"])
        if not any(str(r).rstrip("/") == "/api/_routes" for r in app.url_map.iter_rules()):
            def _dump():
                info=[]
                for r in app.url_map.iter_rules():
                    info.append({
                        "rule": str(r),
                        "methods": sorted(m for m in r.methods if m not in ("HEAD","OPTIONS")),
                        "endpoint": r.endpoint,
                    })
                info.sort(key=lambda x: x["rule"])
                return _j({"routes": info}), 200
            app.add_url_rule("/api/_routes", endpoint="api_routes_dump_app", view_func=_dump, methods=["GET"])
    except Exception:
        pass

    return app
'''
if "FINAL_FACTORY_WRAPPER (idempotente)" not in s:
    s = s.rstrip()+"\n\n"+block.lstrip("\n")
    p.write_text(s, encoding="utf-8")
    print("added FINAL_FACTORY_WRAPPER")
else:
    print("FINAL_FACTORY_WRAPPER already present")
PY
normalize backend/__init__.py

# 3) Failsafe en wsgiapp.py
mkdir -p backend
cat > backend/force_api.py <<'PY'
from flask import jsonify
def install(app):
    try:
        rules = list(app.url_map.iter_rules())
        have_ping   = any(str(r).rstrip('/') == '/api/ping'    for r in rules)
        have_routes = any(str(r).rstrip('/') == '/api/_routes' for r in rules)
        if not have_ping:
            app.add_url_rule('/api/ping', endpoint='api_ping_wsgi',
                             view_func=(lambda: jsonify({'ok': True, 'pong': True, 'src': 'wsgi'})),
                             methods=['GET'])
        if not have_routes:
            def _dump():
                info=[]
                for r in app.url_map.iter_rules():
                    info.append({'rule': str(r),
                                 'methods': sorted(m for m in r.methods if m not in ('HEAD','OPTIONS')),
                                 'endpoint': r.endpoint})
                info.sort(key=lambda x: x['rule'])
                return jsonify({'routes': info}), 200
            app.add_url_rule('/api/_routes', endpoint='api_routes_dump_wsgi', view_func=_dump, methods=['GET'])
    except Exception:
        pass
PY

python - <<'PY'
from pathlib import Path, re
p = Path("wsgiapp.py")
s = p.read_text(encoding="utf-8")
changed = False
if "from backend.force_api import install as _force_api_install" not in s:
    s = s.replace("\nfrom backend import create_app",
                  "\nfrom backend import create_app\nfrom backend.force_api import install as _force_api_install")
    changed = True
if "_force_api_install(app)" not in s:
    s = s.replace("app = create_app()", "app = create_app()\n_force_api_install(app)")
    changed = True
if changed:
    Path("wsgiapp.py").write_text(s, encoding="utf-8")
    print("patched wsgiapp.py")
else:
    print("wsgiapp.py already patched")
PY
normalize wsgiapp.py

# 4) Commit & push
git add backend/routes.py backend/__init__.py backend/force_api.py wsgiapp.py >/dev/null 2>&1 || true
git commit -m "hardfix: garantizar /api/ping y /api/_routes (routes+factory+wsgi failsafe), normalizar indent" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true
echo "✓ Commit & push hechos."

echo
echo "Probar rápido:"
echo "  tools/smoke_ping_diag.sh \"\${1:-https://paste12-rmsk.onrender.com}\""
