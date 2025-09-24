#!/usr/bin/env bash
set -Eeuo pipefail

ROUTES="backend/routes.py"

echo "➤ Backup"
cp -f "$ROUTES" "$ROUTES.bak.$(date +%s)" 2>/dev/null || true

python - <<'PY'
from pathlib import Path, re
p = Path("backend/routes.py")
s = p.read_text(encoding="utf-8")

# 1) Asegurar que /_routes NO tenga /api/ delante dentro del blueprint
#    (soporta comillas simples/dobles)
s_new = re.sub(r'@api\.route\(\s*[\'"]/api/_routes[\'"]', '@api.route("/_routes")', s)

# 2) Asegurar /runtime correcto (por si quedó alguna variante)
s_new = re.sub(r'@api\.route\(\s*[\'"]/api/runtime[\'"]', '@api.route("/runtime")', s_new)

# 3) Asegurar /fs está presente (diagnóstico de filesystem)
if "def api_fs(" not in s_new:
    s_new += r'''

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
            kids = []
            for x in p.iterdir():
                if x.name.startswith("."):
                    continue
                kids.append(x.name + ("/" if x.is_dir() else ""))
                if len(kids) >= 200: break
            info["list"] = sorted(kids)
        except Exception as e:
            info["list_error"] = str(e)
    return jsonify(info), 200
'''
p.write_text(s_new, encoding="utf-8")
print("Rutas de diagnóstico corregidas/aseguradas.")
PY

echo "➤ Commit & push"
git add backend/routes.py
git commit -m "fix(api): corregir _routes/runtime (sin /api dentro del blueprint) + asegurar /api/fs diag" || true
git push origin main

echo
echo "➤ Comandos de prueba (cuando Render tome el deploy)"
cat <<'EOS'
BASE="https://paste12-rmsk.onrender.com"

echo "--- /api/health ---"
curl -sS -D- -o /dev/null "$BASE/api/health" | sed -n '1,12p'

echo "--- /api/_routes ---"
curl -sS "$BASE/api/_routes" | python -m json.tool | sed -n '1,120p'

echo "--- /api/runtime ---"
curl -sS "$BASE/api/runtime" | python -m json.tool

echo "--- /api/fs?path=backend ---"
curl -sS "$BASE/api/fs?path=backend" | python -m json.tool

echo "--- /api/fs?path=backend/frontend ---"
curl -sS "$BASE/api/fs?path=backend/frontend" | python -m json.tool
EOS
