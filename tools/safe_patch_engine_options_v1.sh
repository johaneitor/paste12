#!/usr/bin/env bash
set -euo pipefail
FILE="backend/__init__.py"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
BAK="${FILE}.${TS}.engineopts.bak"

[[ -f "$FILE" ]] || { echo "ERROR: falta $FILE"; exit 2; }
cp -f "$FILE" "$BAK"
echo "[engineopts] Backup: $BAK"

python - <<'PY'
import io,re,os,py_compile
p="backend/__init__.py"
s=io.open(p,"r",encoding="utf-8").read()

# Asegurar imports
if not re.search(r'(?m)^import\s+os\b', s): s="import os\n"+s
if not re.search(r'(?m)^import\s+re\b', s): s="import re\n"+s

# Normalizar DATABASE_URL → SQLALCHEMY_DATABASE_URI (solo si falta)
if not re.search(r'(?m)app\.config\[\s*[\'"]SQLALCHEMY_DATABASE_URI[\'"]\s*\]\s*=', s):
    inject = (
        'uri = os.getenv("DATABASE_URL", "")\n'
        'if uri:\n'
        '    uri = re.sub(r"^postgres://", "postgresql://", uri)\n'
        '    app.config["SQLALCHEMY_DATABASE_URI"] = uri\n'
    )
    # Insertar después de "app = Flask("
    s=re.sub(r'(?m)^(app\s*=\s*Flask\([^\n]*\)\s*\n)', r'\1'+inject, s)

# Añadir ENGINE_OPTIONS si falta
if not re.search(r'(?m)app\.config\[\s*[\'"]SQLALCHEMY_ENGINE_OPTIONS[\'"]\s*\]\s*=', s):
    inject = (
        'app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {\n'
        '    "pool_pre_ping": True,\n'
        '    "pool_recycle": int(os.getenv("DB_POOL_RECYCLE", "300")),\n'
        '    "pool_size": int(os.getenv("DB_POOL_SIZE", "5")),\n'
        '    "max_overflow": int(os.getenv("DB_MAX_OVERFLOW", "5")),\n'
        '}\n'
    )
    s=re.sub(r'(?m)^(app\s*=\s*Flask\([^\n]*\)\s*\n)', r'\1'+inject, s)

# Garantizar TRACK_MODIFICATIONS=False (si faltaba)
if not re.search(r'(?m)app\.config\[\s*[\'"]SQLALCHEMY_TRACK_MODIFICATIONS[\'"]\s*\]\s*=', s):
    s=re.sub(r'(?m)^(app\s*=\s*Flask\([^\n]*\)\s*\n)', r'\1app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False\n', s)

io.open(p,"w",encoding="utf-8").write(s)
py_compile.compile(p, doraise=True)
print("[engineopts] py_compile OK")
PY
