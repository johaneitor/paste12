#!/usr/bin/env bash
set -euo pipefail
TARGET="backend/__init__.py"
[[ -f "$TARGET" ]] || { echo "ERROR: falta $TARGET"; exit 1; }

python - <<'PY'
import io,re
p="backend/__init__.py"
s=io.open(p,"r",encoding="utf-8").read(); orig=s

if "from sqlalchemy.exc import OperationalError" not in s:
    s="from sqlalchemy.exc import OperationalError\n"+s
if "import psycopg2" not in s:
    s="import psycopg2\n"+s

if "@app.errorhandler(OperationalError)" not in s:
    s += (
        "\n\n@app.errorhandler(OperationalError)\n"
        "def _sa_operational(e):\n"
        "    from flask import jsonify\n"
        "    try: db.session.remove()\n"
        "    except Exception: pass\n"
        "    return jsonify(ok=False,error='db_unavailable',detail='OperationalError'),503\n"
    )
if "@app.errorhandler(psycopg2.OperationalError)" not in s:
    s += (
        "\n\n@app.errorhandler(psycopg2.OperationalError)\n"
        "def _psycopg_operational(e):\n"
        "    from flask import jsonify\n"
        "    try: db.session.remove()\n"
        "    except Exception: pass\n"
        "    return jsonify(ok=False,error='db_unavailable',detail='psycopg2.OperationalError'),503\n"
    )

if s!=orig:
    io.open(p,"w",encoding="utf-8").write(s)
    print("[handlers] añadidos para SQLAlchemy y psycopg2")
else:
    print("[handlers] ya estaban")
PY

python -m py_compile backend/__init__.py && echo "py_compile OK"
