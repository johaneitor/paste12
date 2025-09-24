#!/usr/bin/env bash
set -euo pipefail

TARGET="backend/__init__.py"
[[ -f "$TARGET" ]] || { echo "ERROR: falta $TARGET"; exit 2; }

TS="$(date -u +%Y%m%d-%H%M%SZ)"
BAK="${TARGET}.${TS}.indentfix.bak"
cp -f "$TARGET" "$BAK"
echo "[fix] Backup: $BAK"

python - <<'PY'
import io, re

p = "backend/__init__.py"
s = io.open(p, "r", encoding="utf-8").read()
orig = s

# Normalizar EOL y tabs
s = s.replace("\r\n","\n").replace("\r","\n").replace("\t","    ")

def dedent_marker_block(text, marker):
    i = text.find(marker)
    if i == -1:
        return text
    # llevar el bloque al nivel 0 de indentación (línea del marker)
    line_start = text.rfind("\n", 0, i) + 1
    m = re.match(r"[ \t]+", text[line_start:])
    if m:
        ws = m.group(0)
        text = text[:line_start] + text[line_start+len(ws):]
    return text

# 1) Asegurar el bloque "normalize DATABASE_URL" en top-level
s = dedent_marker_block(s, "# == paste12: normalize DATABASE_URL ==")
# por si la 'def' quedó indentada
s = re.sub(r'(?m)^[ \t]+(def _normalize_db_url\()', r'\1', s)

# 2) Quitar cualquier ENGINE_OPTIONS previo (para no duplicar)
s = re.sub(r'(?ms)^\s*app\.config\[\s*[\'"]SQLALCHEMY_ENGINE_OPTIONS[\'"]\s*\]\s*=\s*\{.*?\}\s*', '', s)
s = re.sub(r'(?ms)^\s*app\.config\.setdefault\(\s*[\'"]SQLALCHEMY_ENGINE_OPTIONS[\'"]\s*,\s*\{.*?\}\s*\)\s*', '', s)

# 3) Localizar anchor top-level: app = Flask(
m = re.search(r'(?m)^\s*app\s*=\s*Flask\(', s)
insert_at = m.end() if m else None

opts = (
    '\napp.config.setdefault("SQLALCHEMY_ENGINE_OPTIONS", {\n'
    '    "pool_pre_ping": True,\n'
    '    "pool_recycle": 180,\n'
    '    "pool_timeout": 15,\n'
    '    "pool_size": 5,\n'
    '    "max_overflow": 10,\n'
    '})\n'
)
uri = '\napp.config.setdefault("SQLALCHEMY_DATABASE_URI", os.environ.get("DATABASE_URL", "sqlite:///local.db"))\n'

# 4) Insertar opciones/URI justo después del anchor (si faltan)
if insert_at is not None:
    if "SQLALCHEMY_ENGINE_OPTIONS" not in s:
        s = s[:insert_at] + "\n" + opts + s[insert_at:]
    if "SQLALCHEMY_DATABASE_URI" not in s:
        s = s[:insert_at] + "\n" + uri + s[insert_at:]
else:
    # Sin anchor: apéndice al final como último recurso (top-level)
    tail = ""
    if "SQLALCHEMY_ENGINE_OPTIONS" not in s:
        tail += "\n" + opts
    if "SQLALCHEMY_DATABASE_URI" not in s:
        tail += "\n" + uri
    s = s.rstrip() + tail + "\n"

# 5) Compactar líneas en blanco excesivas
s = re.sub(r'\n{3,}', '\n\n', s)

if s != orig:
    io.open(p, "w", encoding="utf-8").write(s)
    print("[fix] Reescritura aplicada")
else:
    print("[fix] Nada que cambiar")

PY

echo "[fix] Probando compilación…"
if python -m py_compile backend/__init__.py; then
  echo "[fix] py_compile OK"
else
  echo "[fix] ERROR de compilación. Restaure el backup: $BAK"
  cp -f "$BAK" "$TARGET"
  exit 1
fi
