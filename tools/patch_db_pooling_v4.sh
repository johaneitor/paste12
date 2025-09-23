#!/usr/bin/env bash
set -euo pipefail

tgt="backend/__init__.py"
[[ -f "$tgt" ]] || { echo "ERROR: falta $tgt"; exit 1; }

bak="backend/__init__.$(date -u +%Y%m%d-%H%M%SZ).bak"
cp -f "$tgt" "$bak"
echo "[db-pooling] Backup: $bak"

python - <<'PY'
import io, os, re, json

p = "backend/__init__.py"
s = io.open(p, "r", encoding="utf-8").read()
orig = s

def ensure_cfg_block(s):
    # Asegura ENGINE_OPTIONS y normaliza DATABASE_URL
    if "SQLALCHEMY_ENGINE_OPTIONS" not in s:
        s = re.sub(
            r"(app\.config\[['\"]SQLALCHEMY_TRACK_MODIFICATIONS['\"]\]\s*=\s*False\s*)",
            r"""\\1
# Engine hardening
app.config['SQLALCHEMY_ENGINE_OPTIONS'] = {
    'pool_pre_ping': True,
    'pool_recycle': 280,
    'pool_size': 2,
    'max_overflow': 4
}
""",
            s, count=1, flags=re.I
        )
    # Normalizar DATABASE_URL -> postgresql+psycopg2 + sslmode=require
    # Casos: os.environ.get('DATABASE_URL') o literal
    def norm_url(m):
        expr = m.group(1)
        return expr + r"""
# === Normalize DATABASE_URL (protocol + SSL) ===
import urllib.parse as _u
_dburl = app.config.get('SQLALCHEMY_DATABASE_URI') or os.environ.get('DATABASE_URL','')
if _dburl.startswith('postgres://'):
    _dburl = 'postgresql+psycopg2://' + _dburl[len('postgres://'):]
elif _dburl.startswith('postgresql://'):
    _dburl = 'postgresql+psycopg2://' + _dburl[len('postgresql://'):]
# sslmode=require si no está
if 'sslmode=' not in _dburl:
    sep = '&' if '?' in _dburl else '?'
    _dburl = _dburl + f"{sep}sslmode=require"
app.config['SQLALCHEMY_DATABASE_URI'] = _dburl
"""
    # Insertamos tras la línea donde se setea la URI por primera vez
    s = re.sub(
        r"(app\.config\[['\"]SQLALCHEMY_DATABASE_URI['\"]\]\s*=\s*.+\n)",
        norm_url, s, count=1
    )
    return s

def ensure_handlers(s):
    if "def _db_fail" in s and "SQLALCHEMY_ENGINE_OPTIONS" in s:
        return s
    add = r"""
# --- DB error handlers (coherentes) ---
from sqlalchemy.exc import OperationalError, DBAPIError
from flask import jsonify

def _db_fail(e):
    # No revela detalles
    return jsonify({"ok": False, "db": "unavailable"}), 503

@app.errorhandler(OperationalError)
def _operr(e): return _db_fail(e)

@app.errorhandler(DBAPIError)
def _dberr(e): return _db_fail(e)
"""
    # Insertamos cerca del final (tras crear app/db)
    if "Flask(" in s and "SQLAlchemy(" in s:
        s += add
    else:
        s = s + "\n" + add
    return s

s = ensure_cfg_block(s)
s = ensure_handlers(s)

if s != orig:
    io.open(p, "w", encoding="utf-8").write(s)
    print("[db-pooling] aplicado OK")
else:
    print("[db-pooling] ya estaba OK")
PY

python -m py_compile backend/__init__.py && echo "py_compile OK"
