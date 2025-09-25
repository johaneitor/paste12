#!/usr/bin/env bash
set -euo pipefail

TARGET="backend/__init__.py"
[[ -f "$TARGET" ]] || { echo "ERROR: falta $TARGET"; exit 1; }

TS="$(date -u +%Y%m%d-%H%M%SZ)"
cp -f "$TARGET" "${TARGET}.${TS}.bak"
echo "[fix] Backup: ${TARGET}.${TS}.bak"

python - <<'PY'
import io, re, sys
p="backend/__init__.py"
s=io.open(p,"r+",encoding="utf-8").read()
orig=s

# 1) Arreglar definicion segura del handler de fallback
def_block = re.compile(r"(?ms)^\s*def\s+_api_unavailable\s*\([^)]*\)\s*:\s*.*?(?=^\s*def\s+|\Z)")
handler = (
    "def _api_unavailable(exc: Exception):\n"
    "    # Fallback cuando las rutas API no se han registrado aún\n"
    "    from flask import jsonify\n"
    "    return jsonify(error=\"API routes not loaded\", detail=str(exc)), 500\n"
)

if def_block.search(s):
    s = def_block.sub(handler, s)
else:
    # si no existe, lo inyectamos al final del archivo
    if not s.endswith("\n"): s += "\n"
    s += "\n" + handler + "\n"

# 2) Asegurar que el decorador/registro no referencie 'e' fuera de scope
#   Cualquier lambda o wrapper que haga 'detail=str(e)' sin captar 'e' => reemplazar por uso de 'exc'
s = re.sub(r"detail\s*=\s*str\(\s*e\s*\)", "detail=str(exc)", s)

# 3) Micro-saneo de indentación accidental (tabs/espacios mezclados en zonas críticas)
s = re.sub(r"(?m)^\t", "    ", s)

if s!=orig:
    io.open(p,"w",encoding="utf-8").write(s)
    print("[fix] backend/__init__.py actualizado")
else:
    print("[fix] backend/__init__.py ya estaba OK")
PY

python -m py_compile backend/__init__.py && echo "py_compile OK" || { echo "py_compile FAIL"; exit 2; }
echo "Listo. Haz deploy y probamos."
