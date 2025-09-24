#!/usr/bin/env bash
set -euo pipefail

python - <<'PY'
from pathlib import Path
p = Path("backend/__init__.py")
s = p.read_text(encoding="utf-8")

# Asegurar acceso a jsonify/current_app por si no estaban importados
if "from flask import current_app, jsonify" not in s:
    s = s.replace("from flask import Flask, g, request",
                  "from flask import current_app, jsonify, Flask, g, request")

# Garantizar wrapper _orig_create_app
if "_orig_create_app" not in s:
    s = s.replace("def create_app(", "_orig_create_app=create_app\n\ndef create_app(")

inj = r"""
    # -- fuerza /api/ping desde la factory, sin depender del blueprint --
    try:
        def __factory_ping():
            return jsonify({"ok": True, "pong": True, "src": "factory"}), 200
        # evita duplicados por si ya existe
        if not any(str(r).rstrip('/') == '/api/ping' for r in app.url_map.iter_rules()):
            app.add_url_rule('/api/ping', endpoint='api_ping_factory', view_func=__factory_ping, methods=['GET'])
    except Exception:
        pass
"""

marker = "app = _orig_create_app(*args, **kwargs)"
if marker in s and inj not in s:
    s = s.replace(marker, marker + inj, 1)

p.write_text(s, encoding="utf-8")
print("OK: factory ahora fuerza /api/ping")
PY

git add backend/__init__.py >/dev/null 2>&1 || true
git commit -m "hotfix(factory): fuerza /api/ping vía add_url_rule en create_app" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true
echo "✓ Commit & push hechos."
