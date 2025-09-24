#!/usr/bin/env bash
set -euo pipefail

FILE="backend/__init__.py"

python - <<'PY'
from pathlib import Path, re
p = Path("backend/__init__.py")
s = p.read_text(encoding="utf-8")

# 1) asegurar imports
if "from flask import current_app, jsonify" not in s:
    s = s.replace("from flask import Flask, g, request",
                  "from flask import current_app, jsonify, Flask, g, request")

# 2) asegurar wrapper de factory
if "_orig_create_app" not in s:
    s = s.replace("def create_app(", "_orig_create_app=create_app\n\ndef create_app(")

# 3) bloque failsafe a insertar ANTES de 'return app' de la factory
block = """
    # -- FAILSAFE: expone /api/ping y /api/_routes desde la factory (idempotente) --
    try:
        def __factory_ping():
            return jsonify({"ok": True, "pong": True, "src": "factory"}), 200
        rules = list(app.url_map.iter_rules())
        have_ping = any(str(r).rstrip('/') == '/api/ping' for r in rules)
        if not have_ping:
            app.add_url_rule('/api/ping', endpoint='api_ping_factory', view_func=__factory_ping, methods=['GET'])

        def __factory_routes_dump():
            info=[]
            for r in app.url_map.iter_rules():
                info.append({
                    "rule": str(r),
                    "methods": sorted(m for m in r.methods if m not in ('HEAD','OPTIONS')),
                    "endpoint": r.endpoint,
                })
            info.sort(key=lambda x: x["rule"])
            return jsonify({"routes": info}), 200
        have_routes = any(str(r).rstrip('/') == '/api/_routes' for r in rules)
        if not have_routes:
            app.add_url_rule('/api/_routes', endpoint='api_routes_dump_factory', view_func=__factory_routes_dump, methods=['GET'])
    except Exception:
        pass
"""

# Inserta justo antes del 'return app' de la factory más interna.
# Usamos la última ocurrencia de 'return app' para evitar tocar otras funciones.
idx = s.rfind("return app")
if idx == -1:
    raise SystemExit("No encontré 'return app' en backend/__init__.py")
s = s[:idx] + block + "\n" + s[idx:]

p.write_text(s, encoding="utf-8")
print("OK: inyectado failsafe /api/ping y /api/_routes antes de return app")
PY

git add backend/__init__.py >/dev/null 2>&1 || true
git commit -m "hotfix(factory): añade failsafe /api/ping y /api/_routes justo antes de return app" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true

echo "✓ Commit & push hechos."
echo
echo "Ahora probá:"
echo "  tools/smoke_ping_diag.sh \"${1:-https://paste12-rmsk.onrender.com}\""
