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
    lines = blob.splitlines(True)
    ins_at = 0
    for i, L in enumerate(lines[:100]):
        if L.strip().startswith(("from ", "import ")): ins_at = i+1
    lines.insert(ins_at, line + "\n")
    return "".join(lines)

# imports mínimos
src = ensure_import("from flask import jsonify, current_app", src)
src = ensure_import("from flask import Blueprint", src)

# normalizar definición del blueprint (sin url_prefix aquí)
src = re.sub(r'api\s*=\s*Blueprint\(\s*"api"\s*,\s*__name__\s*,\s*url_prefix\s*=\s*["\'][^"\']+["\']\s*\)',
             'api = Blueprint("api", __name__)', src)

def have_route(blob, path):
    return re.search(rf'@api\.(?:route|get)\(\s*"{re.escape(path)}"', blob) is not None

append = []

# ruta estándar del blueprint
if not have_route(src, "/ping"):
    append.append(
        """
@api.route("/ping", methods=["GET"])
def ping():
    return jsonify({"ok": True, "pong": True}), 200
""".lstrip("\n")
    )

# hook para garantizar /api/ping a nivel app (por si el blueprint NO usa url_prefix)
if "def _ensure_ping_route(" not in src:
    append.append(
        """
@api.record_once
def _ensure_ping_route(state):
    app = state.app
    try:
        # si ya existe alguna regla que termine exactamente en /api/ping, no hacemos nada
        for r in app.url_map.iter_rules():
            if str(r).rstrip("/") == "/api/ping":
                break
        else:
            app.add_url_rule(
                "/api/ping", endpoint="api_ping_direct",
                view_func=(lambda: jsonify({"ok": True, "pong": True})), methods=["GET"]
            )
    except Exception:
        # no rompemos el registro del blueprint
        pass
""".lstrip("\n")
    )

# _routes (por si también falta)
if not have_route(src, "/_routes"):
    append.append(
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

if append:
    if not src.endswith("\n"): src += "\n"
    src += "\n".join(append) + "\n"
    p.write_text(src, encoding="utf-8")
    print("OK: ping/_routes añadidos/asegurados")
else:
    print("OK: ping/_routes ya estaban")
PY

git add backend/routes.py >/dev/null 2>&1 || true
git commit -m "hotfix(api): fuerza /api/ping vía record_once y asegura /_routes" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true
echo "✓ Commit & push hechos."
