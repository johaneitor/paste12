#!/usr/bin/env bash
set -euo pipefail

TARGET="backend/__init__.py"
[[ -f "$TARGET" ]] || { echo "ERROR: falta $TARGET"; exit 1; }

python - <<'PY'
import io, re, sys
p = "backend/__init__.py"
s = io.open(p, "r", encoding="utf-8").read()
orig = s

# 1) Asegurar importaciones
if "from flask_sqlalchemy import SQLAlchemy" not in s:
    s = s.replace("from flask import", "from flask_sqlalchemy import SQLAlchemy\nfrom flask import")

if "from sqlalchemy.exc import OperationalError" not in s:
    s = "from sqlalchemy.exc import OperationalError\n" + s

# 2) Asegurar instancia global de db (idempotente)
if re.search(r"^db\s*=\s*SQLAlchemy\(\)", s, re.M) is None:
    s = s.replace("\napp = ", "\ndb = SQLAlchemy()\n\napp = ")

# 3) Inject en create_app(): engine options sanas
def inject_engine_opts(block: str) -> str:
    if "SQLALCHEMY_ENGINE_OPTIONS" in block:
        return block  # ya presente
    inj = (
        '    # --- DB pooling sano ---\n'
        '    app.config.setdefault("SQLALCHEMY_ENGINE_OPTIONS", {\n'
        '        "pool_pre_ping": True,\n'
        '        "pool_recycle": 300,\n'
        '        "pool_size": 5,\n'
        '        "max_overflow": 5,\n'
        '        "pool_timeout": 10,\n'
        '    })\n'
    )
    return block + "\n" + inj

s = re.sub(
    r"(def\s+create_app\(.*?\):\s*\n(?:.*\n)*?)(\n\s*#|\n\s*from|\n\s*app\.|$)",
    lambda m: inject_engine_opts(m.group(1)) + m.group(2),
    s, count=1, flags=re.S
)

# 4) Asegurar init de db con app dentro de create_app()
if re.search(r"db\.init_app\(\s*app\s*\)", s) is None:
    s = re.sub(r"(def\s+create_app\(.*?\):\s*\n)", r"\1    db.init_app(app)\n", s, count=1)

# 5) Handler 503 amable para OperationalError
if "@app.errorhandler(OperationalError)" not in s:
    s += (
        "\n\n@app.errorhandler(OperationalError)\n"
        "def _db_op_error(e):\n"
        "    from flask import jsonify\n"
        "    try:\n"
        "        db.session.remove()\n"
        "    except Exception:\n"
        "        pass\n"
        "    return jsonify(ok=False, error=\"db_unavailable\", detail=str(e.__class__.__name__)), 503\n"
    )

if s != orig:
    io.open(p, "w", encoding="utf-8").write(s)
    print("[db-pooling] backend/__init__.py actualizado")
else:
    print("[db-pooling] ya estaba OK")

PY

# Gate rápido
python -m py_compile backend/__init__.py  && echo "py_compile OK"

echo "Listo. Vuelve a desplegar con tu Start Command habitual."
