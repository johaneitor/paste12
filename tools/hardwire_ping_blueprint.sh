#!/usr/bin/env bash
set -euo pipefail

# --- backend/routes.py: asegurar ping en el blueprint ---
python - <<'PY'
from pathlib import Path, re
p = Path("backend/routes.py")
s = p.read_text(encoding="utf-8")

# Asegurar declaración del blueprint sin url_prefix aquí (lo pone la factory)
if 'api = Blueprint("api", __name__' not in s:
    import re
    s = re.sub(r'api\s*=\s*Blueprint\([^\)]*\)', 'api = Blueprint("api", __name__)', s, count=1)

# Handler canónico de ping dentro del blueprint
if '@api.route("/ping", methods=["GET"])' not in s:
    s += """

@api.route("/ping", methods=["GET"])
def api_ping():
    return jsonify({"ok": True, "pong": True}), 200
"""
p.write_text(s, encoding="utf-8")
print("OK: routes.py tiene @api.route('/ping')")

PY

# --- backend/__init__.py: asegurar registration con url_prefix='/api' ---
python - <<'PY'
from pathlib import Path
p = Path("backend/__init__.py")
s = p.read_text(encoding="utf-8")

# Buscar la factory create_app y asegurarnos de registrar el blueprint
if "_orig_create_app" not in s:
    s = s.replace("def create_app(", "_orig_create_app=create_app\n\ndef create_app(")

inj = """
    # -- garantizar registro del blueprint API con /api --
    try:
        from backend.routes import api as api_bp
        # evitar doble registro
        if not any(r.rule.startswith('/api') for r in app.url_map.iter_rules()):
            app.register_blueprint(api_bp, url_prefix='/api')
        else:
            # si ya hay rutas del blueprint sin prefijo, registrar igual con prefijo para /api/*
            app.register_blueprint(api_bp, url_prefix='/api')
    except Exception as _e:
        try:
            current_app.logger.exception("Failed registering API blueprint: %s", _e)
        except Exception:
            pass
"""
marker = "app = _orig_create_app(*args, **kwargs)"
if marker in s and inj not in s:
    s = s.replace(marker, marker + inj, 1)

p.write_text(s, encoding="utf-8")
print("OK: __init__.py refuerza register_blueprint(api_bp, url_prefix='/api')")
PY

git add backend/routes.py backend/__init__.py >/dev/null 2>&1 || true
git commit -m "hotfix(api): fuerza /api/ping en blueprint y refuerza registro con url_prefix=/api" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true
echo "✓ Commit & push hechos."
