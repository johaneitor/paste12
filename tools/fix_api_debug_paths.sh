#!/usr/bin/env bash
set -Eeuo pipefail

ROUTES="backend/routes.py"

echo "➤ Backup"
cp -f "$ROUTES" "$ROUTES.bak.$(date +%s)" 2>/dev/null || true

python - <<'PY'
from pathlib import Path, re
p = Path("backend/routes.py")
s = p.read_text(encoding="utf-8")

# 1) Corregir decoradores mal puestos dentro del blueprint `api`
#    /api/_routes  ->  /_routes   (porque el blueprint ya añade /api)
#    /api/runtime  ->  /runtime
s = re.sub(r'@api\.route\(\s*["\']/api/_routes["\']', '@api.route("/_routes"', s)
s = re.sub(r'@api\.route\(\s*["\']/api/runtime["\']', '@api.route("/runtime"', s)

# 2) Asegurar endpoint /api/fs (diagnóstico de filesystem)
if "def api_fs(" not in s:
    extra = r'''
from pathlib import Path
from flask import request, jsonify

@api.route("/fs", methods=["GET"])  # /api/fs?path=backend/frontend
def api_fs():
    q = request.args.get("path", ".")
    p = Path(q)
    info = {
        "path": str(p.resolve()),
        "exists": p.exists(),
        "is_dir": p.is_dir(),
        "list": None,
    }
    if p.exists() and p.is_dir():
        try:
            info["list"] = sorted([x for x in p.iterdir() if x.name[:1] != "." and x.is_file() or x.is_dir()])[:200]
            info["list"] = [str(x.name) for x in info["list"]]
        except Exception as e:
            info["list_error"] = str(e)
    return jsonify(info), 200
'''.strip("\n") + "\n"
    # insertar cerca del final para no romper nada
    s += "\n" + extra

p.write_text(s, encoding="utf-8")
print("Rutas corregidas y /api/fs garantizado.")
PY

echo "➤ Commit & push"
git add backend/routes.py
git commit -m "fix(api): corregir decoradores en _routes/runtime (sin /api dentro del blueprint) + agregar /api/fs diag"
git push origin main

echo "✓ Parche enviado."
