#!/usr/bin/env bash
set -euo pipefail
P="backend/__init__.py"
[[ -f "$P" ]] || { echo "ERROR: falta $P"; exit 1; }
TS="$(date -u +%Y%m%d-%H%M%SZ)"
cp -f "$P" "${P}.${TS}.bak"

python - <<'PY'
import io,re,sys
p="backend/__init__.py"
s=io.open(p,"r",encoding="utf-8").read()

# 1) Asegurar import de CORS para evitar NameError en resoluciones tempranas
if "from flask_cors import CORS" not in s:
    s = s.replace("from flask import", "from flask_cors import CORS\nfrom flask import")

# 2) Reemplazar handler _api_unavailable para que no use 'e'
pat=r"def\s+_api_unavailable\([^)]*\):[\s\S]*?return\s+jsonify\(.*?\),\s*500"
new=(
"def _api_unavailable():\n"
"    # Handler de respaldo cuando las rutas /api aún no están montadas\n"
"    from flask import jsonify\n"
"    return jsonify(error=\"API routes not loaded\"), 500\n"
)
s2=re.sub(pat,"".join(new),s,flags=re.M)

# 3) Si no existe, registrar un blueprint/route minimal para /api/health (idempotente)
if "/api/health" not in s2:
    inj=(
"\n# -- Salud mínima, independiente de DB --\n"
"try:\n"
"    from flask import Blueprint, jsonify\n"
"    _p12_health_bp = Blueprint('p12_health', __name__)\n"
"    @_p12_health_bp.route('/api/health', methods=['GET'])\n"
"    def _p12_health():\n"
"        return jsonify(ok=True, api=True, ver='factory-v2')\n"
"    try:\n"
"        app.register_blueprint(_p12_health_bp)\n"
"    except Exception:\n"
"        pass\n"
"except Exception:\n"
"    pass\n"
)
    # insertar antes del final del archivo, de forma segura
    s2 = s2 + inj

if s2!=s:
    io.open(p,"w",encoding="utf-8").write(s2)
    print("[fix] backend/__init__.py actualizado")
else:
    print("[fix] nada que cambiar (ya estaba fijo)")
PY

python -m py_compile backend/__init__.py && echo "py_compile OK"
echo "Listo. Haz deploy."
