#!/usr/bin/env bash
set -euo pipefail
_red(){ printf "\033[31m%s\033[0m\n" "$*"; }; _grn(){ printf "\033[32m%s\033[0m\n" "$*"; }

FILE="backend/__init__.py"
[[ -f "$FILE" ]] || { _red "No existe $FILE"; exit 1; }

python - <<'PY'
from pathlib import Path, re
p=Path("backend/__init__.py")
s=p.read_text(encoding="utf-8")

# Asegurar import jsonify/current_app si falta
if "from flask import jsonify" not in s:
    s = s.replace("from flask import", "from flask import jsonify,")
if "from flask import current_app" not in s:
    if "from flask import" in s:
        s = s.replace("from flask import ", "from flask import current_app, ")

# Localizar create_app y meter las rutas si no existen
if "def create_app(" not in s:
    raise SystemExit("No encuentro create_app en backend/__init__.py")

block = """
    # -- app-level safety routes (idempotentes) --
    try:
        if not any(r.rule == '/api/ping' for r in app.url_map.iter_rules()):
            from flask import jsonify as _j
            app.add_url_rule('/api/ping', 'api_ping', lambda: _j({'pong': True}), methods=['GET'])
        if not any(r.rule == '/api/_routes' for r in app.url_map.iter_rules()):
            from flask import jsonify as _j
            def _dump_routes():
                info=[]
                for r in app.url_map.iter_rules():
                    info.append({'rule': str(r),
                                 'methods': sorted(m for m in r.methods if m not in ('HEAD','OPTIONS')),
                                 'endpoint': r.endpoint})
                info.sort(key=lambda x: x['rule'])
                return _j({'routes': info}), 200
            app.add_url_rule('/api/_routes', 'api_routes_dump_app', _dump_routes, methods=['GET'])
    except Exception:
        pass
"""

# Inserta el bloque antes del 'return app' de create_app si aún no está
if "/api/ping" not in s or "/api/_routes" not in s:
    s = re.sub(r"(def\s+create_app\([^\)]*\):\s*\n(?:.*\n)*?)(\s*return\s+app\s*)",
               lambda m: m.group(1) + block + "\n" + m.group(2),
               s, count=1)
p.write_text(s, encoding="utf-8")
print("OK: hotfix app-level /api/ping y /api/_routes añadidos")
PY

git add backend/__init__.py >/dev/null 2>&1 || true
git commit -m "hotfix(app): añade /api/ping y /api/_routes a nivel app para estabilizar smoke" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true
_grn "✓ Commit & push hechos."
echo
echo "Ahora probá:"
echo "  tools/smoke_ping_routes.sh \"\${1:-https://paste12-rmsk.onrender.com}\""
