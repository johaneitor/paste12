#!/usr/bin/env bash
set -euo pipefail

python - <<'PY'
from pathlib import Path, re
p = Path("wsgiapp.py")
s = p.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n")

# ya existen?
has_ping = re.search(r"@app\.get\(\s*['\"]/api/ping['\"]\s*\)", s) is not None
has_routes = re.search(r"@app\.get\(\s*['\"]/api/_routes['\"]\s*\)", s) is not None

injection = """
# --- WSGI DIRECT API ENDPOINTS (decorators, no blueprints) ---
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
"""

if not (has_ping and has_routes):
    # Insertar después de __whoami (si existe) o al final del archivo
    anchor = re.search(r"@app\.get\(\s*['\"]/__whoami['\"]\s*\)[\s\S]*?\n\)", s)
    if anchor:
        idx = anchor.end()
        s = s[:idx] + "\n" + injection + "\n" + s[idx:]
    else:
        s = s.rstrip() + "\n\n" + injection + "\n"
    p.write_text(s, encoding="utf-8")
    print("patched wsgiapp.py (direct /api/ping and /api/_routes)")
else:
    print("wsgiapp.py already has direct endpoints; no changes.")
PY

git add wsgiapp.py >/dev/null 2>&1 || true
git commit -m "hotfix(wsgiapp): add direct /api/ping and /api/_routes (decorators, no blueprints)" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true

echo "✓ Commit & push hechos."
echo "Proba:"
echo "  tools/smoke_ping_diag.sh \"\${1:-https://paste12-rmsk.onrender.com}\""
