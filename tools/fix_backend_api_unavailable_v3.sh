#!/usr/bin/env bash
set -euo pipefail
FILE="backend/__init__.py"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
[[ -f "$FILE" ]] || { echo "ERROR: falta $FILE"; exit 1; }
cp -f "$FILE" "$FILE.$TS.apiunavail.bak"
echo "[fix] Backup: $FILE.$TS.apiunavail.bak"

python3 - <<'PY'
import io, re, sys, os
p="backend/__init__.py"
s=io.open(p,"r",encoding="utf-8").read()
orig=s

# 1) Asegurar import jsonify
if not re.search(r'\bfrom\s+flask\s+import\b.*\bjsonify\b', s):
    # si existe alguna línea 'from flask import ...', añadimos jsonify ahí
    m=re.search(r'^(from\s+flask\s+import[^\n]+)$', s, re.M)
    if m:
        line=m.group(1)
        if 'jsonify' not in line:
            s=s.replace(line, line.replace('\n','') + ', jsonify')
    else:
        # no hay import de flask aún: insertamos tras el primer bloque de imports
        s=re.sub(r'(^\s*import[^\n]+\n(?:\s*from[^\n]+\n|\s*import[^\n]+\n)*)',
                 r'\1from flask import jsonify\n', s, count=1, flags=re.M)

# 2) Reemplazar/crear _api_unavailable(e)
stub = (
    "def _api_unavailable(e: Exception):\n"
    "    # Fallback global para cuando las rutas no cargan\n"
    "    # Evita NameError y devuelve JSON coherente\n"
    "    try:\n"
    "        msg = (str(e) if e is not None else \"unavailable\")[:500]\n"
    "    except Exception:\n"
    "        msg = \"unavailable\"\n"
    "    return jsonify(error=\"API routes not loaded\", detail=msg), 500\n"
)
if re.search(r'^\s*def\s+_api_unavailable\b', s, re.M):
    # Sustituir función completa hasta el siguiente def a la izquierda
    s = re.sub(
        r'(^\s*def\s+_api_unavailable[^\n]*:\n)(?:\s.*\n)*?(?=^\s*def\s+\w|\Z)',
        stub + "\n",
        s, flags=re.M
    )
else:
    # Insertar cerca de create_app() o al final
    m=re.search(r'^\s*def\s+create_app\b[^\n]*:\n', s, re.M)
    if m:
        idx=m.start()
        s = s[:idx] + stub + "\n" + s[idx:]
    else:
        s = s + "\n\n" + stub + "\n"

# 3) Dentro de create_app, asegurar register_error_handler antes de 'return app'
def inject_handler(body:str)->str:
    # Detectar indent del 'return app'
    m=re.search(r'^(?P<indent>\s*)return\s+app\b', body, re.M)
    if not m:
        return body
    indent = m.group('indent')
    handler = f"{indent}# asegurar fallback de errores\n{indent}app.register_error_handler(Exception, _api_unavailable)\n"
    if re.search(r'register_error_handler\s*\(\s*Exception\s*,\s*_api_unavailable\s*\)', body):
        return body
    # Insertar justo antes del return app
    body = re.sub(r'^(?P<indent>\s*)return\s+app\b', handler + r'\g<indent>return app', body, count=1, flags=re.M)
    return body

def repl_create_app(m):
    head=m.group(1)
    body=m.group(2)
    tail=m.group(3)
    body2=inject_handler(body)
    return head+body2+tail

if re.search(r'^\s*def\s+create_app\b[^\n]*:\n', s, re.M):
    s = re.sub(r'(^\s*def\s+create_app[^\n]*:\n)(.*?)(^\S|\Z)', repl_create_app, s, flags=re.S|re.M)
# Limpiezas de indent accidentales dobles
s = re.sub(r'[ \t]+$', '', s, flags=re.M)

if s!=orig:
    io.open(p,"w",encoding="utf-8").write(s)
    print("[fix] backend/__init__.py actualizado")
else:
    print("[fix] Nada que cambiar")

PY

python3 - <<'PY'
import py_compile
py_compile.compile("backend/__init__.py", doraise=True)
print("py_compile OK")
PY
echo "Listo. (Si tenías un IndentationError, debería quedar resuelto)."
