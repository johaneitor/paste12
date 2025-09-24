#!/usr/bin/env bash
set -Eeuo pipefail

PYFILE="backend/debug_routes.py"
cat > "$PYFILE" <<'PY'
from flask import Blueprint, jsonify, current_app
debug_api = Blueprint("debug_api", __name__)

@debug_api.get("/api/_routes")
def list_routes():
    app = current_app
    info = []
    for rule in app.url_map.iter_rules():
        info.append({
            "rule": str(rule),
            "methods": sorted([m for m in rule.methods if m not in ("HEAD", "OPTIONS")]),
            "endpoint": rule.endpoint,
        })
    return jsonify({"routes": sorted(info, key=lambda r: r["rule"])}), 200
PY

# Registrar el blueprint en el WSGI de entrada (desacoplado del init)
PATCH="backend/entry.py"
if ! grep -q "from backend.debug_routes import debug_api" "$PATCH"; then
  awk '
    1
    /app = _app/ && !x { print "\n# Registrar endpoint de depuracion de rutas"; print "try:"; print "    from backend.debug_routes import debug_api"; print "    app.register_blueprint(debug_api)"; print "except Exception:"; print "    pass"; x=1 }
  ' "$PATCH" > "$PATCH.tmp" && mv "$PATCH.tmp" "$PATCH"
fi

git add backend/debug_routes.py backend/entry.py
git commit -m "chore(debug): agregar /api/_routes y registrarlo desde entry.py"
git push origin main

echo "Ahora probá:"
echo "  curl -sS https://paste12-rmsk.onrender.com/api/_routes | python -m json.tool | head -n 80"
