#!/usr/bin/env bash
set -euo pipefail

TARGET="backend/__init__.py"
[[ -f "$TARGET" ]] || { echo "ERROR: falta $TARGET"; exit 1; }
TS="$(date -u +%Y%m%d-%H%M%SZ)"
BAK="$TARGET.$TS.bak"
cp -f "$TARGET" "$BAK"
echo "[indent+pool v2] Backup: $BAK"

python - <<'PY'
import io, re, sys, os
p="backend/__init__.py"
s=io.open(p, "r", encoding="utf-8").read()

# 1) Normalizar whitespace para reducir chances de indent raro
s = s.replace("\r\n","\n").replace("\r","\n").replace("\t","    ")

# 2) Quitar restos de bloques previos para no duplicar
s = re.sub(r'\n# == Paste12 DB pool hardening ==[\s\S]*?# == /DB pool hardening ==\n','\n', s)
s = re.sub(r'\n# == Paste12 harden v2 ==[\s\S]*?# == /Paste12 harden v2 ==\n','\n', s)
s = re.sub(r'app\.config\[\s*["\']SQLALCHEMY_TRACK_MODIFICATIONS["\']\s*\]\s*=\s*(True|False)\s*\n','', s)

# 3) Inyectar al final, en top-level, dentro de try/except
append = '''
# == Paste12 harden v2 ==
try:
    # Desactivar track_modifications de forma segura
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
except Exception:
    pass
try:
    # Normalizar DATABASE_URL (postgres:// → postgresql://)
    uri = app.config.get("SQLALCHEMY_DATABASE_URI") or app.config.get("DATABASE_URL") or ""
    if uri.startswith("postgres://"):
        uri = "postgresql://" + uri.split("postgres://",1)[1]
        app.config["SQLALCHEMY_DATABASE_URI"] = uri

    # Endurecimiento del pool
    engine_opts = {
        "pool_pre_ping": True,
        "pool_recycle": 280,
        "pool_size": 5,
        "max_overflow": 5,
        "pool_use_lifo": True,
    }
    if "postgresql://" in (app.config.get("SQLALCHEMY_DATABASE_URI") or ""):
        engine_opts["connect_args"] = {
            "keepalives": 1, "keepalives_idle": 30, "keepalives_interval": 10, "keepalives_count": 5
        }
    app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {
        **engine_opts, **app.config.get("SQLALCHEMY_ENGINE_OPTIONS", {})
    }
except Exception:
    # No romper el boot por detalles de configuración
    pass
# == /Paste12 harden v2 ==
'''.lstrip()

if not s.endswith("\n"): s += "\n"
s = s + append
io.open(p,"w",encoding="utf-8").write(s)
PY

# 4) Gate de sintaxis
if python -m py_compile backend/__init__.py 2>/dev/null; then
  echo "[indent+pool v2] py_compile OK"
else
  echo "[indent+pool v2] py_compile FAIL"
  exit 2
fi

echo "Listo. Vuelve a desplegar cuando quieras."
