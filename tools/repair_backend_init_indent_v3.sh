#!/usr/bin/env bash
set -euo pipefail

FILE="backend/__init__.py"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
BAK="${FILE}.${TS}.bak"

[[ -f "$FILE" ]] || { echo "ERROR: falta $FILE"; exit 2; }
cp -f "$FILE" "$BAK"
echo "[indent-fix] Backup: $BAK"

python - <<'PY'
import io,re,sys,py_compile

p="backend/__init__.py"
s=io.open(p,"r",encoding="utf-8").read()

# Normalizaciones básicas
s=s.replace("\r\n","\n").replace("\r","\n").replace("\t","    ")

# Dedentar cosas que DEBEN estar a nivel toplevel
patterns=[
    r'app\s*=\s*Flask\(',                     # app = Flask(...)
    r'app\.config\[[^\n]+',                   # app.config["..."] = ...
    r'db\s*=\s*SQLAlchemy\(',                 # db = SQLAlchemy(app)
    r'migrate\s*=\s*\w*\(?',                  # migrate = ...
    r'@app\.route\(',                         # decoradores en raíz
    r'SQLAlchemy\(',                          # por si quedó solo
    r'app\.register_blueprint\(',             # blueprints (si los hay)
]
for pat in patterns:
    s=re.sub(r'(?m)^[ ]{1,12}('+pat+')', r'\1', s)

# Si faltan imports útiles, los añadimos de forma inocua (idempotente)
def ensure(line, after_pat):
    global s
    if re.search(re.escape(line), s): return
    m=re.search(after_pat, s, re.M)
    if m:
        idx=m.end()
        s=s[:idx]+"\n"+line+s[idx:]
    else:
        s=line+"\n"+s

ensure("import os, re", r'(?m)^from\s+flask')
# No forzamos SQLAlchemy import si ya existe
if not re.search(r'(?m)^from\s+flask_sqlalchemy\s+import\s+SQLAlchemy', s):
    s=s.replace("from flask import Flask", "from flask import Flask\nfrom flask_sqlalchemy import SQLAlchemy")

# Asegurar que ciertos app.config estén en toplevel y existan
if not re.search(r'(?m)app\.config\[\s*[\'"]SQLALCHEMY_TRACK_MODIFICATIONS[\'"]\s*\]\s*=', s):
    s=s.replace("app = Flask(", "app = Flask(")  # marcador
    s=re.sub(r'(?m)^(app\s*=\s*Flask\([^\n]*\).*\n)', r'\1app.config[\"SQLALCHEMY_TRACK_MODIFICATIONS\"] = False\n', s)

# Guardar y compilar
io.open(p,"w",encoding="utf-8").write(s)
try:
    py_compile.compile(p, doraise=True)
    print("[indent-fix] py_compile OK")
except Exception as e:
    print("[indent-fix] py_compile FAIL:", e)
    # Muestra un contexto para localizar la línea
    src=io.open(p,"r",encoding="utf-8").read().splitlines()
    for i,line in enumerate(src,1):
        pref=">>" if i in getattr(e,'lineno',[]) if isinstance(getattr(e,'lineno',None),list) else []
        if i>= (getattr(e,'lineno',0)-3) and i<= (getattr(e,'lineno',0)+3):
            print(f"{i:4d}: {line}")
    sys.exit(3)
PY
