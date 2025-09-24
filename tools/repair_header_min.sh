#!/usr/bin/env bash
set -euo pipefail

F="render_entry.py"
[ -f "$F" ] || { echo "[!] No existe $F"; exit 1; }

BKP="$F.bak.$(date +%Y%m%d-%H%M%S)"
cp -a "$F" "$BKP"
echo "[i] Backup en $BKP"

# Buscamos el primer bloque donde empiezan las rutas para cortar ahí
CUT_LINE="$(grep -n -m1 'Blueprint API' "$F" | cut -d: -f1 || true)"
if [ -z "${CUT_LINE:-}" ]; then
  CUT_LINE="$(wc -l < "$F")"
fi

TMP="$(mktemp)"
{
cat <<'PYHEAD'
from __future__ import annotations
import os, hashlib
from datetime import datetime, timedelta
from flask import Flask, Blueprint, jsonify, request

# --- safe default for NOTE_TABLE (evita NameError al importar en Render) ---
import os as _os
NOTE_TABLE = _os.environ.get('NOTE_TABLE', 'note')
# ---------------------------------------------------------------------------

app = None
db = None
Note = None

# 1) Intenta usar tu factory/ORM reales si existen
try:
    from backend import create_app, db as _db
    from backend.models import Note as _Note
    app = create_app()
    db = _db
    Note = _Note
except Exception:
    pass

# 2) Fallback mínimo si no hay factory/ORM
if app is None:
    from flask_sqlalchemy import SQLAlchemy
    app = Flask(__name__)
    app.config["SQLALCHEMY_DATABASE_URI"] = os.environ.get("DATABASE_URL", "sqlite:///app.db")
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    db = SQLAlchemy(app)

    class Note(db.Model):
        __tablename__ = NOTE_TABLE
        id = db.Column(db.Integer, primary_key=True)
        text = db.Column(db.Text, nullable=False)
        timestamp = db.Column(db.DateTime, nullable=False, index=True, default=datetime.utcnow)
        expires_at = db.Column(db.DateTime, nullable=False, index=True, default=datetime.utcnow)
        likes = db.Column(db.Integer, default=0, nullable=False)
        views = db.Column(db.Integer, default=0, nullable=False)
        reports = db.Column(db.Integer, default=0, nullable=False)
        author_fp = db.Column(db.String(64), nullable=False, index=True, default="noctx")

def _now() -> datetime:
    return datetime.utcnow()

def _fp() -> str:
    try:
        ip = request.headers.get("X-Forwarded-For","") or request.headers.get("CF-Connecting-IP","") or (request.remote_addr or "")
        ua = request.headers.get("User-Agent","")
        salt = os.environ.get("FP_SALT","")
        return hashlib.sha256(f"{ip}|{ua}|{salt}".encode()).hexdigest()[:32]
    except Exception:
        return "noctx"

def _has(path:str, method:str) -> bool:
    for r in app.url_map.iter_rules():
        if str(r) == path and method.upper() in r.methods:
            return True
    return False

def _note_json(n: Note, now: datetime | None = None) -> dict:
    now = now or _now()
    toiso = lambda d: (d.isoformat() if d else None)
    return {
        "id": n.id,
        "text": n.text,
        "timestamp": toiso(getattr(n, "timestamp", None)),
        "expires_at": toiso(getattr(n, "expires_at", None)),
        "likes": getattr(n, "likes", 0),
        "views": getattr(n, "views", 0),
        "reports": getattr(n, "reports", 0),
        "author_fp": getattr(n, "author_fp", None),
        "now": now.isoformat(),
    }
PYHEAD

# Pegamos el resto del archivo desde la línea de corte para preservar tus rutas
tail -n +"$CUT_LINE" "$F"
} > "$TMP"

mv "$TMP" "$F"
echo "[ok] Header reescrito de forma limpia hasta la sección de rutas (línea $CUT_LINE)"

# Compilación rápida
echo "[i] Compilando con py_compile…"
python -m py_compile "$F" && echo "[✓] Compila OK"
