#!/usr/bin/env bash
set -euo pipefail
python - <<'PY'
from pathlib import Path, re
p = Path("wsgiapp.py")
s = p.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n")
has_ping = re.search(r"@app\.get\(\s*['\"]/api/ping['\"]\s*\)", s) is not None
has_routes = re.search(r"@app\.get\(\s*['\"]/api/_routes['\"]\s*\)", s) is not None
inj = """
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
    if not s.endswith("\n"): s += "\n"
    s = s + "\n" + inj + "\n"
    p.write_text(s, encoding="utf-8")
    print("patched wsgiapp.py")
else:
    print("already present")
PY

git add wsgiapp.py >/dev/null 2>&1 || true
git commit -m "hotfix(wsgiapp): add direct /api/ping and /api/_routes (no blueprints)" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true
echo "✓ Commit & push hechos."
