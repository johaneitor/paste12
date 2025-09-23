#!/usr/bin/env bash
set -euo pipefail

F="backend/__init__.py"
[[ -f "$F" ]] || { echo "ERROR: falta $F"; exit 1; }
TS="$(date -u +%Y%m%d-%H%M%SZ)"
cp -f "$F" "$F.$TS.bak"
echo "[fix] Backup: $F.$TS.bak"

python - <<'PY'
import io, re, sys

p = "backend/__init__.py"
s = io.open(p, "r", encoding="utf-8").read()
orig = s

# Normalizar texto
s = s.replace("\r\n","\n").replace("\r","\n")   # EOLs
s = s.replace("\xa0"," ")                       # NBSP → espacio
s = s.expandtabs(4)                             # tabs → 4 espacios

# Dejar sin sangría TODAS las asignaciones app.config[...] (evita 'unexpected indent')
s = re.sub(r'(?m)^[ \t]+(app\.config\[[^\]]+\]\s*=.*)$', r'\1', s)

# Asegurar TRACK_MODIFICATIONS = False
if 'SQLALCHEMY_TRACK_MODIFICATIONS' not in s:
    s = re.sub(r'(?m)^(app\s*=\s*Flask\([^)]*\)\s*)$',
               r'\1\napp.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False',
               s, count=1)
else:
    s = re.sub(r'(?m)^app\.config\["SQLALCHEMY_TRACK_MODIFICATIONS"\]\s*=.*$',
               'app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False', s)

# Inyectar opciones de pool seguras si faltan
if 'SQLALCHEMY_ENGINE_OPTIONS' not in s:
    block = (
        '\n# Pooling seguro para Render/psycopg2\n'
        'app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {\n'
        '    "pool_pre_ping": True,\n'
        '    "pool_recycle": 280,\n'
        '    "pool_size": 5,\n'
        '    "max_overflow": 10,\n'
        '}\n'
    )
    s = re.sub(r'(?m)^(app\s*=\s*Flask\([^)]*\)\s*)$',
               r'\1\n' + block, s, count=1)

# Limpieza de espacios al final de línea
s = re.sub(r'[ \t]+(\n)', r'\1', s)

if s != orig:
    io.open(p, "w", encoding="utf-8").write(s)
    print("[fix] __init__ normalizado")
else:
    print("[fix] Nada que cambiar")

PY

# Validación con contexto si falla
python - <<'PY'
import py_compile, sys, linecache, re
try:
    py_compile.compile('backend/__init__.py', doraise=True)
    print("[fix] py_compile OK")
except Exception as e:
    print("[fix] py_compile FAIL:", e)
    m = re.search(r'line (\d+)', str(e))
    if m:
        ln = int(m.group(1))
        start = max(1, ln-6); end = ln+6
        for i in range(start, end+1):
            print(f"{i:4d}: "+linecache.getline('backend/__init__.py', i), end='')
    sys.exit(2)
PY

echo "[fix] Listo. Ahora deploya en Render (Clear build cache) con el Start Command:"
echo "  gunicorn wsgi:application --chdir /opt/render/project/src -w \${WEB_CONCURRENCY:-2} -k gthread --threads \${THREADS:-4} --timeout \${TIMEOUT:-120} -b 0.0.0.0:\$PORT"
