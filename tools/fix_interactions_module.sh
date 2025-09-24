#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"

echo "[+] Escribiendo backend/modules/interactions.py (módulo encapsulado, sin unlike, idempotente)…"
mkdir -p backend/modules
cat > backend/modules/interactions.py <<'PY'
from __future__ import annotations
import os, math
from datetime import datetime, timezone
from typing import Optional

from flask import Blueprint, jsonify, request, current_app
from sqlalchemy import UniqueConstraint, Index, func

# Intentar usar ORM real del proyecto
db = None
Note = None
try:
    from backend import db as _db
    from backend.models import Note as _Note
    db, Note = _db, _Note
except Exception as _e:
    # Fallback mínimo si se usa este módulo suelto
    from flask_sqlalchemy import SQLAlchemy
    from flask import Flask
    _app = current_app._get_current_object() if current_app else None
    if _app is None:
        _app = Flask(__name__)
        _app.config["SQLALCHEMY_DATABASE_URI"] = os.environ.get("DATABASE_URL","sqlite:///app.db")
        _app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    db = SQLAlchemy(_app)
    class Note(db.Model):
        __tablename__ = "note"
        id = db.Column(db.Integer, primary_key=True)
        text = db.Column(db.Text, nullable=False)
        timestamp = db.Column(db.DateTime, nullable=False, index=True)
        expires_at = db.Column(db.DateTime, nullable=False, index=True)
        likes = db.Column(db.Integer, default=0, nullable=False)
        views = db.Column(db.Integer, default=0, nullable=False)
        reports = db.Column(db.Integer, default=0, nullable=False)
        author_fp = db.Column(db.String(64), nullable=False, default="noctx", index=True)

def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)

def _fp() -> str:
    ip = request.headers.get("X-Forwarded-For","") or request.headers.get("CF-Connecting-IP","") or (request.remote_addr or "")
    ua = request.headers.get("User-Agent","")
    salt = os.environ.get("FP_SALT","")
    import hashlib
    try:
        return hashlib.sha256(f"{ip}|{ua}|{salt}".encode()).hexdigest()[:32]
    except Exception:
        return "noctx"

# === Modelo de eventos (sin unlike). Idempotencia por constraints ===
class InteractionEvent(db.Model):
    __tablename__ = "interaction_event"
    id = db.Column(db.Integer, primary_key=True)
    note_id = db.Column(db.Integer, db.ForeignKey("note.id", ondelete="CASCADE"), nullable=False, index=True)
    fp = db.Column(db.String(64), nullable=False, index=True)
    # 'like' | 'view'
    type = db.Column(db.String(16), nullable=False, index=True)
    # bucket_15m: ventana de 15 minutos (views); para like queda 0
    bucket_15m = db.Column(db.Integer, nullable=False, default=0, index=True)
    created_at = db.Column(db.DateTime, nullable=False, default=_utcnow, index=True)

    __table_args__ = (
        # Un like por usuario por nota (idempotente)
        UniqueConstraint('note_id', 'fp', 'type',
                         name='uq_like_per_user',
                         deferrable=True, initially='DEFERRED'),
        # Una view por usuario por nota por bucket de 15 min (idempotente x ventana)
        UniqueConstraint('note_id', 'fp', 'type', 'bucket_15m',
                         name='uq_view_15m_per_user',
                         deferrable=True, initially='DEFERRED'),
        Index('ix_evt_note_type_bucket', 'note_id', 'type', 'bucket_15m'),
    )

bp = Blueprint("interactions", __name__)

def _bucket_15m(ts: Optional[datetime] = None) -> int:
    ts = ts or _utcnow()
    # epoch seconds // 900
    epoch = ts.timestamp()
    return int(math.floor(epoch / 900.0))

def _note_or_404(note_id: int) -> Optional[Note]:
    n = Note.query.filter_by(id=note_id).first()
    return n

@bp.post("/notes/<int:note_id>/like")
def like_note(note_id: int):
    n = _note_or_404(note_id)
    if not n:
        return jsonify(ok=False, error="not_found"), 404
    fp = _fp()
    try:
        # Insert idempotente: like => bucket=0
        evt = InteractionEvent(note_id=note_id, fp=fp, type="like", bucket_15m=0)
        db.session.add(evt)
        db.session.commit()
    except Exception:
        # Violación de unique (ya likeó): ignorar
        db.session.rollback()
    # Recalcular contador denormalizado
    likes = db.session.query(func.count(InteractionEvent.id)).filter_by(note_id=note_id, type="like").scalar() or 0
    n.likes = int(likes)
    db.session.commit()
    return jsonify(ok=True, id=note_id, likes=n.likes), 200

@bp.post("/notes/<int:note_id>/view")
def view_note(note_id: int):
    n = _note_or_404(note_id)
    if not n:
        return jsonify(ok=False, error="not_found"), 404
    fp = _fp()
    b = _bucket_15m()
    try:
        evt = InteractionEvent(note_id=note_id, fp=fp, type="view", bucket_15m=b)
        db.session.add(evt)
        db.session.commit()
    except Exception:
        db.session.rollback()
    views = db.session.query(func.count(InteractionEvent.id)).filter_by(note_id=note_id, type="view").scalar() or 0
    n.views = int(views)
    db.session.commit()
    return jsonify(ok=True, id=note_id, views=n.views, window="15m"), 200

@bp.get("/notes/<int:note_id>/stats")
def stats_note(note_id: int):
    n = _note_or_404(note_id)
    if not n:
        return jsonify(ok=False, error="not_found"), 404
    likes = db.session.query(func.count(InteractionEvent.id)).filter_by(note_id=note_id, type="like").scalar() or 0
    views = db.session.query(func.count(InteractionEvent.id)).filter_by(note_id=note_id, type="view").scalar() or 0
    return jsonify(ok=True, id=note_id, likes=int(likes), views=int(views), denorm={"likes":n.likes,"views":n.views}), 200

def ensure_schema():
    try:
        db.create_all()
    except Exception:
        pass

def register_into(app):
    # idempotente: si ya existen, no rompe
    try:
        app.register_blueprint(bp, url_prefix="/api")
    except Exception:
        pass
    with app.app_context():
        ensure_schema()

# Auto-registro cuando el módulo se importa y hay app activa (opcional)
try:
    _app = current_app._get_current_object()
    if _app:
        register_into(_app)
except Exception:
    pass
PY

echo "[+] Asegurando creación de esquema (create_all) desde un contexto…"
python - <<'PY'
import importlib
from flask import Flask
try:
    # intentar usar app real si existe
    app = None
    for modname in ("render_entry","wsgi","run"):
        try:
            m = importlib.import_module(modname)
            app = getattr(m, "app", None)
            if app:
                break
        except Exception:
            pass
    if app is None:
        app = Flask(__name__)
        from flask_sqlalchemy import SQLAlchemy
        app.config["SQLALCHEMY_DATABASE_URI"] = "sqlite:///app.db"
        app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
        SQLAlchemy(app)
    with app.app_context():
        mod = importlib.import_module("backend.modules.interactions")
        mod.ensure_schema()
        try:
            mod.register_into(app)
        except Exception:
            pass
    print("[OK] Schema listo y blueprint registrado (si aplica).")
except Exception as e:
    print("[!] No se pudo crear esquema:", repr(e))
PY

echo "[+] Inyectando auto-registro seguro en wsgi.py/run.py/render_entry.py (si existen)…"
patch_entry() {
  local F="$1"
  [ -f "$F" ] || return 0
  if grep -q "interactions_module_autoreg" "$F"; then
    echo "    - ya parchado $F"
    return 0
  fi
  echo "    - parchando $F"
  cat >> "$F" <<'PY'

# >>> interactions_module_autoreg
try:
    from backend.modules.interactions import register_into as _interactions_register
    try:
        from flask import current_app as _cap
        _app = _cap._get_current_object() if _cap else app
    except Exception:
        _app = app if 'app' in globals() else None
    if _app is not None:
        _interactions_register(_app)
except Exception:
    # silencioso: no romper el arranque si falta algo
    pass
# <<< interactions_module_autoreg
PY
}
patch_entry wsgi.py
patch_entry run.py
patch_entry render_entry.py

echo "[+] Listo. Reinicia tu app local y luego corre tools/test_integral_interactions.sh"
