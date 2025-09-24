#!/usr/bin/env bash
set -euo pipefail
_red(){ printf "\033[31m%s\033[0m\n" "$*"; }
_grn(){ printf "\033[32m%s\033[0m\n" "$*"; }

FILE="backend/routes.py"
[[ -f "$FILE" ]] || { _red "No existe $FILE"; exit 1; }

python - <<'PY'
from pathlib import Path, re
p = Path("backend/routes.py")
src = p.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n").replace("\t","    ")

# Reemplazar TODO el bloque de admin_cleanup() por una versión canónica
pat = re.compile(
    r'@api\.route\("/admin/cleanup",\s*methods=\["POST","GET"\]\)\s*[\r\n]+def\s+admin_cleanup\(\)\s*:[\s\S]*?(?=\n@api\.route|\Z)',
    re.M
)

new_block = r'''
@api.route("/admin/cleanup", methods=["POST","GET"])
def admin_cleanup():
    token = os.getenv("ADMIN_TOKEN","")
    provided = (request.args.get("token") or request.headers.get("X-Admin-Token") or "")
    if not token or provided != token:
        return jsonify({"error":"forbidden"}), 403
    try:
        from flask import current_app
        from backend.__init__ import _cleanup_once
        _cleanup_once(current_app)
        return jsonify({"ok": True}), 200
    except Exception as e:
        return jsonify({"error": "cleanup_failed", "detail": str(e)}), 500
'''.strip("\n")

if not pat.search(src):
    print("No se encontró admin_cleanup(); no se cambia nada")
else:
    src = pat.sub(new_block + "\n", src, count=1)
    p.write_text(src, encoding="utf-8")
    print("OK: admin_cleanup() reescrita de forma canónica")
PY

git add backend/routes.py >/dev/null 2>&1 || true
git commit -m "hotfix(routes): reescribe admin_cleanup() con bloque try/except correctamente indentado" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true

_grn "✓ Commit & push hechos."
echo
echo "Ahora corre el smoke:"
echo "  tools/run_system_smoke.sh \"https://paste12-rmsk.onrender.com\""
