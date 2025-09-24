#!/usr/bin/env bash
set -euo pipefail
PYTHON=${PYTHON:-python}

file="backend/__init__.py"
[[ -f "$file" ]] || { echo "ERROR: falta $file"; exit 1; }

ts="$(date -u +%Y%m%d-%H%M%SZ)"
bak="${file}.${ts}.bak"
cp -f "$file" "$bak"
echo "[soft-guard] Backup: $bak"

$PYTHON - <<'PY'
import io, re, os
p="backend/__init__.py"
s=io.open(p,"r",encoding="utf-8").read()
orig=s

# Asegurar imports mínimos
def ensure(line,head):
    return (line+"\n"+head) if head not in line else line

s=ensure(s,"from flask import Flask, request, jsonify")
s=ensure(s,"from flask_cors import CORS")
s=ensure(s,"import os")
s=ensure(s,"from datetime import timedelta")

# Habilitar CORS si no está
if "CORS(" not in s:
    s=re.sub(r'(app\s*=\s*Flask\(.*?\))',
             r'\1\nCORS(app, resources={r"/api/*": {"origins": "*"}}, supports_credentials=False)',
             s, count=1, flags=re.S)

# Engine options (pooling, sslmode)
if "SQLALCHEMY_ENGINE_OPTIONS" not in s:
    s=re.sub(r'(app\.config\[[\'"]SQLALCHEMY_TRACK_MODIFICATIONS[\'"]\]\s*=\s*False.*\n)?',
             (r"app.config.setdefault('SQLALCHEMY_TRACK_MODIFICATIONS', False)\n"
              r"app.config.setdefault('SQLALCHEMY_ENGINE_OPTIONS', {\n"
              r"  'pool_pre_ping': True,\n"
              r"  'pool_recycle': int(os.environ.get('DB_POOL_RECYCLE','270')),\n"
              r"  'pool_size': int(os.environ.get('DB_POOL_SIZE','2')),\n"
              r"  'max_overflow': int(os.environ.get('DB_MAX_OVERFLOW','2')),\n"
              r"  'connect_args': {'sslmode': os.environ.get('PGSSLMODE','require')}\n"
              r"})\n"),
             s, count=1, flags=re.S)

# Guard suave: sólo escrituras, nunca OPTIONS, GET ni HEAD
block = """
# == soft DB guard / helpers ==
try:
    from sqlalchemy import text
except Exception:
    text = None

def _db_ping_ok(app, db):
    if not text:  # sin SQLAlchemy text, salir "ok"
        return True
    try:
        with db.engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return True
    except Exception as e:
        try:
            app.logger.warning("db ping fail: %s", e)
        except Exception:
            pass
        return False

def _install_soft_db_guard(app, db):
    @app.before_request
    def _only_guard_writes():
        # dejar pasar health y todo GET/HEAD/OPTIONS
        if request.method in ("GET","HEAD","OPTIONS"):
            return None
        if not request.path.startswith("/api/"):
            return None
        if not _db_ping_ok(app, db):
            return ("Service temporarily unavailable (db)", 503, {"Content-Type":"text/plain"})
        return None
"""
if "def _install_soft_db_guard(" not in s:
    s += "\n"+block+"\n"

# Colgar el guard si hay 'db' y 'app'
if "._install_soft_db_guard(app, db)" not in s and "_install_soft_db_guard(app, db)" not in s:
    s = re.sub(r'(db\.init_app\(app\).*\n)', r'\1\n_install_soft_db_guard(app, db)\n', s, flags=re.S)

# Health fallback (por si el blueprint no la da)
if "/api/health" not in s:
    s += """
@app.get("/api/health")
def _health_fallback():
    return jsonify({"ok": True, "api": True, "ver": "soft-guard-v1"})
"""

if s!=orig:
    io.open(p,"w",encoding="utf-8").write(s)
    print("[soft-guard] backend/__init__.py actualizado")
else:
    print("[soft-guard] No hubo cambios (ya estaba)")
PY

python -m py_compile backend/__init__.py && echo "[soft-guard] py_compile OK"
echo "Listo. Despliega y probamos."
