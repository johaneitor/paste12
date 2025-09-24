#!/usr/bin/env bash
set -euo pipefail

file="wsgiapp.py"
[[ -f "$file" ]] || { echo "No existe $file"; exit 1; }

python - <<'PY'
from pathlib import Path, re
p = Path("wsgiapp.py")
s = p.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n")

# Buscar la creación del app para insertar justo después
m = re.search(r'(?ms)^app\s*=\s*Flask\([^)]*\)\s*\n', s)
if not m:
    raise SystemExit("No pude localizar 'app = Flask(...)' en wsgiapp.py")
insertion = m.end()

block = r'''
# --- WSGI EARLY PIN: rutas mínimas para diagnóstico ---
try:
    from flask import jsonify as _j

    # __version (SHA corto si hay git)
    try:
        import subprocess
        _rev = subprocess.check_output(["git","rev-parse","--short","HEAD"], text=True).strip()
    except Exception:
        _rev = None
    if not any(str(r).rstrip("/") == "/__version" for r in app.url_map.iter_rules()):
        @app.get("/__version")
        def __version():
            return _j({"rev": _rev}), 200

    # /api/ping
    if not any(str(r).rstrip("/") == "/api/ping" for r in app.url_map.iter_rules()):
        @app.get("/api/ping")
        def __ping_wsgi_early():
            return _j({"ok": True, "pong": True, "src": "wsgi-early"}), 200

    # /api/_routes
    if not any(str(r).rstrip("/") == "/api/_routes" for r in app.url_map.iter_rules()):
        @app.get("/api/_routes")
        def __routes_wsgi_early():
            info=[]
            for r in app.url_map.iter_rules():
                info.append({
                    "rule": str(r),
                    "methods": sorted(m for m in r.methods if m not in ("HEAD","OPTIONS")),
                    "endpoint": r.endpoint,
                })
            info.sort(key=lambda x: x["rule"])
            return _j({"routes": info}), 200
except Exception:
    # No rompemos wsgi aunque falle este bloque
    pass
# --- /WSGI EARLY PIN ---
'''
if "WSGI EARLY PIN: rutas mínimas para diagnóstico" not in s:
    s = s[:insertion] + block + "\n" + s[insertion:]
    p.write_text(s, encoding="utf-8")
    print("patched wsgiapp.py")
else:
    print("already present")
PY

git add wsgiapp.py >/dev/null 2>&1 || true
git commit -m "hotfix(wsgi): early-pin /api/ping, /api/_routes y /__version antes de importar backend.routes" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true
echo "✓ Commit & push hechos."
