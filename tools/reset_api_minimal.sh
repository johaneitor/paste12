#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"
mkdir -p .tmp

stamp(){ date +%Y%m%d-%H%M%S; }

# 1) Respaldos
[ -f backend/routes.py ] && cp backend/routes.py "backend/routes.py.bak.$(stamp)"

# 2) Reescribimos backend/routes.py a una versión mínima, correcta y robusta
cat > backend/routes.py <<'PY'
from __future__ import annotations

import os, hashlib
from datetime import datetime, timedelta
from flask import Blueprint, request, jsonify
from backend import db

# Import del modelo Note
try:
    from backend.models import Note
except Exception as e:  # mostramos el error al golpear endpoints
    Note = None
    _import_error = e
else:
    _import_error = None

# Un único blueprint llamado "api"
bp = Blueprint("api", __name__)

def _now() -> datetime:
    # Naive UTC (compatible con la mayoría de definiciones típicas de modelos)
    return datetime.utcnow()

def _fp() -> str:
    try:
        ip = request.headers.get("X-Forwarded-For","") or request.headers.get("CF-Connecting-IP","") or (request.remote_addr or "")
        ua = request.headers.get("User-Agent","")
        salt = os.environ.get("FP_SALT","")
        return hashlib.sha256(f"{ip}|{ua}|{salt}".encode()).hexdigest()[:32]
    except Exception:
        return "noctx"

def _note_json(n: "Note", now: datetime | None = None) -> dict:
    now = now or _now()
    return {
        "id": n.id,
        "text": n.text,
        "timestamp": n.timestamp.isoformat() if hasattr(n.timestamp, "isoformat") else n.timestamp,
        "expires_at": n.expires_at.isoformat() if hasattr(n.expires_at, "isoformat") else n.expires_at,
        "likes": getattr(n, "likes", 0),
        "views": getattr(n, "views", 0),
        "reports": getattr(n, "reports", 0),
        "author_fp": getattr(n, "author_fp", None),
        "now": now.isoformat(),
    }

@bp.route("/health", methods=["GET"])
def health():
    return jsonify({"ok": True})

@bp.route("/notes", methods=["GET"])
def list_notes():
    if Note is None:
        return jsonify({"ok": False, "error": f"Note not importable: {_import_error!r}"}), 500
    try:
        page = int(request.args.get("page", 1))
    except Exception:
        page = 1
    page = max(1, page)
    per_page = 20
    q = Note.query.order_by(Note.timestamp.desc())
    items = q.limit(per_page).offset((page - 1) * per_page).all()
    now = _now()
    return jsonify([_note_json(n, now) for n in items]), 200

@bp.route("/notes", methods=["POST"])
def create_note():
    if Note is None:
        return jsonify({"ok": False, "error": f"Note not importable: {_import_error!r}"}), 500
    try:
        data = request.get_json(silent=True) or {}
        text = (data.get("text") or "").strip()
        if not text:
            return jsonify({"error": "text required"}), 400
        try:
            hours = int(data.get("hours", 24))
        except Exception:
            hours = 24
        hours = min(168, max(1, hours))
        now = _now()
        n = Note(
            text=text,
            timestamp=now,
            expires_at=now + timedelta(hours=hours),
            author_fp=_fp(),
        )
        db.session.add(n)
        db.session.commit()
        return jsonify(_note_json(n, now)), 201
    except Exception as e:
        db.session.rollback()
        return jsonify({"error":"create_failed", "detail": str(e)}), 500

@bp.route("/notes/<int:note_id>/like", methods=["POST"])
def like_note(note_id: int):
    if Note is None:
        return jsonify({"ok": False, "error": f"Note not importable: {_import_error!r}"}), 500
    n = Note.query.get(note_id)
    if not n:
        return jsonify({"error":"not_found"}), 404
    try:
        n.likes = int(getattr(n, "likes", 0)) + 1
        db.session.commit()
        return jsonify({"ok": True, "likes": n.likes, "id": n.id}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"error":"like_failed", "detail": str(e)}), 500
PY

# 3) Verificación de sintaxis rápida
python -m py_compile backend/routes.py || { echo "[!] routes.py con errores de sintaxis"; exit 1; }

# 4) Reinicio y humos
LOG=".tmp/paste12.log"
pkill -f "python .*run.py" 2>/dev/null || true
: > "$LOG" || true
nohup python run.py >"$LOG" 2>&1 &
sleep 2

echo "[+] URL map:"
python - <<'PY' 2>/dev/null || true
import importlib
app = importlib.import_module("run").app
for r in sorted(app.url_map.iter_rules(), key=lambda x: (str(x), sorted(x.methods))):
    m = ",".join(sorted([i for i in r.methods if i not in ("HEAD","OPTIONS")]))
    print(f"{r.rule:30s} {m:10s} {r.endpoint}")
print()
print("HAS /api/notes GET:", any(r.rule=="/api/notes" and "GET" in r.methods for r in app.url_map.iter_rules()))
print("HAS /api/notes POST:", any(r.rule=="/api/notes" and "POST" in r.methods for r in app.url_map.iter_rules()))
PY

PORT="$(grep -Eo '127\.0\.0\.1:[0-9]+' "$LOG" | tail -n1 | cut -d: -f2 || echo 8000)"
echo "[i] PORT_LOCAL=$PORT"

echo "[+] Smoke GET /api/notes"
curl -s -i "http://127.0.0.1:$PORT/api/notes?page=1" | sed -n '1,80p'
echo
echo "[+] Smoke POST /api/notes"
curl -s -i -X POST -H "Content-Type: application/json" \
  -d '{"text":"reset-api-minimal","hours":24}' "http://127.0.0.1:$PORT/api/notes" | sed -n '1,120p'
echo
echo "[+] Tail logs:"
tail -n 100 "$LOG" || true
