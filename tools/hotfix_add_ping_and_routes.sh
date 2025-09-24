#!/usr/bin/env bash
set -euo pipefail

FILE="backend/routes.py"

if [[ ! -f "$FILE" ]]; then
  echo "No existe $FILE" >&2
  exit 1
fi

python - "$FILE" <<'PY'
from pathlib import Path, re
p = Path("backend/routes.py")
src = p.read_text(encoding="utf-8")

def ensure_import(line: str, blob: str) -> str:
    if line in blob:
        return blob
    # Inserta los imports cerca del principio (después del primer bloque de imports si existe)
    lines = blob.splitlines(True)
    ins_at = 0
    for i, L in enumerate(lines[:80]):
        if L.strip().startswith(("from ", "import ")):
            ins_at = i+1
    lines.insert(ins_at, line + "\n")
    return "".join(lines)

# Asegurar imports mínimos
src = ensure_import("from flask import jsonify, current_app", src)
src = ensure_import("from flask import request", src)
src = ensure_import("from flask import Blueprint", src)

# Asegurar que el blueprint no tiene url_prefix aquí (se pone en create_app)
src = re.sub(r'api\s*=\s*Blueprint\(\s*"api"\s*,\s*__name__\s*,\s*url_prefix\s*=\s*["\'][^"\']+["\']\s*\)',
             'api = Blueprint("api", __name__)', src)

def have_route(path: str) -> bool:
    pat = re.compile(rf'@api\.(?:route|get)\(\s*"{re.escape(path)}"')
    return bool(pat.search(src))

append_blocks = []

# /api/ping
if not have_route("/ping"):
    append_blocks.append(
        """
@api.route("/ping", methods=["GET"])
def ping():
    return jsonify({"ok": True, "pong": True}), 200
""".lstrip("\n")
    )

# /api/_routes
if not have_route("/_routes"):
    append_blocks.append(
        """
@api.route("/_routes", methods=["GET"])
def _routes_dump():
    info = []
    for r in current_app.url_map.iter_rules():
        info.append({
            "rule": str(r),
            "methods": sorted(m for m in r.methods if m not in ("HEAD","OPTIONS")),
            "endpoint": r.endpoint,
        })
    info.sort(key=lambda x: x["rule"])
    return jsonify({"routes": info}), 200
""".lstrip("\n")
    )

if append_blocks:
    if not src.endswith("\n"):
        src += "\n"
    src += "\n".join(append_blocks) + "\n"
    p.write_text(src, encoding="utf-8")
    print("OK: ping/_routes agregados")
else:
    print("OK: ping/_routes ya presentes (sin cambios)")
PY

git add backend/routes.py >/dev/null 2>&1 || true
git commit -m "hotfix(api): agrega /api/ping y /api/_routes (idempotente)" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true
echo "✓ Commit & push hechos."
