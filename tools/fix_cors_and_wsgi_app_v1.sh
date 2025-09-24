#!/usr/bin/env bash
set -euo pipefail

PY_FILE="backend/__init__.py"
[[ -f "$PY_FILE" ]] || { echo "ERROR: no existe $PY_FILE"; exit 2; }

TS="$(date -u +%Y%m%d-%H%M%SZ)"
BAK="${PY_FILE}.${TS}.bak"
cp -f "$PY_FILE" "$BAK"
echo "[cors-fix] Backup: $BAK"

python - <<'PY'
import io, re, sys, os
p = "backend/__init__.py"
s = io.open(p, "r", encoding="utf-8").read()
orig = s

def ensure_import_cors(txt):
    if "from flask_cors import CORS" in txt:
        return txt
    # insertar después de otros imports de Flask
    pat = r"(^\s*from\s+flask\s+import[^\n]*\n)"
    if re.search(pat, txt, re.M):
        return re.sub(pat, r"\1from flask_cors import CORS\n", txt, flags=re.M, count=1)
    # fallback: tras el primer import
    return re.sub(r"(^\s*import[^\n]*\n)", r"\1from flask_cors import CORS\n", txt, flags=re.M, count=1)

def ensure_cors_on_app(txt):
    # Caso 1: app = Flask(...)
    m = re.search(r"^\s*app\s*=\s*Flask\([^)]*\)\s*$", txt, re.M)
    if m and "CORS(" not in txt:
        ins = m.group(0) + "\nCORS(app, resources={r\"/*\": {\"origins\": \"*\"}})\n"
        return txt[:m.start()] + ins + txt[m.end():]
    # Caso 2: create_app() define app local
    # Insertar CORS tras la línea app = Flask(...) dentro de create_app
    def repl_in_create(block):
        if "CORS(" in block:
            return block
        mm = re.search(r"^\s*(app\s*=\s*Flask\([^)]*\))\s*$", block, re.M)
        if mm:
            after = mm.group(0) + "\n    CORS(app, resources={r\"/*\": {\"origins\": \"*\"}})"
            return block[:mm.start()] + after + block[mm.end():]
        return block

    def repl_func(mf):
        body = mf.group(0)
        return repl_in_create(body)

    txt2 = re.sub(r"def\s+create_app\s*\([^\)]*\)\s*:[\s\S]*?\n(?=def\s|\Z)", repl_func, txt, flags=re.M)
    return txt2

def ensure_app_symbol(txt):
    # Si no hay 'app = Flask(' a nivel módulo, pero sí create_app, exportar app al final
    if re.search(r"^\s*app\s*=\s*Flask\(", txt, re.M):
        return txt
    if re.search(r"^\s*def\s+create_app\s*\(", txt, re.M):
        if not re.search(r"^\s*app\s*=\s*create_app\(\)\s*$", txt, re.M):
            txt = txt.rstrip() + "\n\n# Exponer app para WSGI\napp = create_app()\n"
    return txt

# 1) Import CORS
s = ensure_import_cors(s)
# 2) Aplicar CORS a app
s = ensure_cors_on_app(s)
# 3) Asegurar símbolo app si sólo hay factory
s = ensure_app_symbol(s)

if s != orig:
    io.open(p, "w", encoding="utf-8").write(s)
    print("[cors-fix] __init__.py actualizado")
else:
    print("[cors-fix] Nada que cambiar (ya estaba OK)")
PY

python -m py_compile backend/__init__.py && echo "[cors-fix] py_compile OK"

echo "Listo. Despliega y probamos."
