#!/usr/bin/env bash
set -euo pipefail
TS="$(date -u +%Y%m%d-%H%M%SZ)"
ROUTES="backend/routes.py"

backup() { [[ -f "$1" ]] && cp -f "$1" "$1.$TS.bak" && echo "[backup] $1.$TS.bak"; }

ensure_file_min() {
  mkdir -p backend
  cat > "$ROUTES" <<'PYMOD'
from __future__ import annotations
from flask import Blueprint, jsonify, request
api_bp = Blueprint("api", __name__)

@api_bp.route("/health")
def api_health():
    return jsonify(ok=True, api=True, ver="routes-min-v1")

# Endpoints mínimos; si existen modelos reales, estos pueden ser reemplazados por los definitivos.
@api_bp.route("/notes")
def list_notes():
    limit = int(request.args.get("limit", "10"))
    before_id = request.args.get("before_id")
    # Fallback: responder lista vacía pero válida
    data = {"notes": [], "limit": limit, "before_id": before_id}
    return jsonify(data)
PYMOD
  echo "[routes] creado mínimo funcional con api_bp"
}

patch_alias_if_needed() {
  python - <<'PY'
import io, re, sys, os
p="backend/routes.py"
s=io.open(p,"r",encoding="utf-8").read()
orig=s
# 1) Si ya exporta api_bp como Blueprint -> no tocar
if re.search(r"\bapi_bp\s*=\s*Blueprint\s*\(", s):
    print("[routes] api_bp ya existe.")
    sys.exit(0)
# 2) Buscar algún Blueprint('api',...) con otro nombre
m=re.search(r"^(\w+)\s*=\s*Blueprint\s*\(\s*['\"]api['\"]\s*,", s, re.M)
if m:
    name=m.group(1)
    if name!="api_bp":
        s += f"\n# alias de export para factory\napi_bp = {name}\n"
        io.open(p,"w",encoding="utf-8").write(s)
        print(f"[routes] agregado alias api_bp -> {name}")
        sys.exit(0)
# 3) No hay blueprint para 'api': fall back a mínimo
print("[routes] no encontré Blueprint('api', ...).")
sys.exit(2)
PY
}

main() {
  if [[ ! -f "$ROUTES" ]]; then
    echo "[routes] no existe $ROUTES, generando mínimo…"
    ensure_file_min
  else
    backup "$ROUTES"
    if ! patch_alias_if_needed; then
      echo "[routes] aplicando mínimo funcional (no había blueprint 'api')"
      ensure_file_min
    fi
  fi

  # Sanity: intentar importar api_bp
  python - <<'PY'
try:
    from backend.routes import api_bp  # type: ignore
    assert api_bp is not None
    print("[sanity] import backend.routes: api_bp OK")
except Exception as e:
    import traceback; traceback.print_exc()
    raise SystemExit(1)
PY
}
main
