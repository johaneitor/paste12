#!/usr/bin/env bash
set -Eeuo pipefail
REPO="$(pwd)"
ROUTES="$REPO/backend/routes.py"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
TMPDIR="${TMPDIR:-$PREFIX/tmp}"
LOG="${TMPDIR}/paste12_server.log"
SERVER="http://127.0.0.1:8000"

mkdir -p "$TMPDIR"
cp -f "$ROUTES" "$ROUTES.bak.$(date +%s)" 2>/dev/null || true

# Escribir un routes.py limpio y estable
cat > "$ROUTES" <<'PYCODE'
from __future__ import annotations

from flask import Blueprint, request, jsonify
from backend import db
from backend.models import Note
from hashlib import sha256
from datetime import datetime, timedelta

# Blueprint principal de API
api = Blueprint("api", __name__, url_prefix="/api")

# Helpers
def _fingerprint_from_request(req):
    ip = (req.headers.get("X-Forwarded-For") or getattr(req, "remote_addr", "") or "").split(",")[0].strip()
    ua = req.headers.get("User-Agent", "")
    raw = f"{ip}|{ua}"
    return sha256(raw.encode("utf-8")).hexdigest()

def _note_to_dict(n: Note):
    return {
        "id": n.id,
        "text": getattr(n, "text", None),
        "timestamp": n.timestamp.isoformat() if getattr(n, "timestamp", None) else None,
        "expires_at": n.expires_at.isoformat() if getattr(n, "expires_at", None) else None,
        "likes": getattr(n, "likes", 0) or 0,
        "views": getattr(n, "views", 0) or 0,
        "reports": getattr(n, "reports", 0) or 0,
    }

# Health
@api.route("/health", methods=["GET"])
def health():
    return jsonify({"ok": True})

# Listar notas (paginado simple)
@api.route("/notes", methods=["GET"])
def list_notes():
    try:
        page = int((request.args.get("page") or "1").strip() or "1")
    except Exception:
        page = 1
    if page < 1:
        page = 1
    q = db.session.query(Note).order_by(Note.id.desc())
    items = q.limit(20).offset((page - 1) * 20).all()
    return jsonify([_note_to_dict(n) for n in items])

# Crear nota
@api.route("/notes", methods=["POST"])
def create_note():
    data = request.get_json(silent=True) or {}
    text = (data.get("text") or "").strip()
    try:
        hours = int(data.get("hours") or 24)
    except Exception:
        hours = 24
    if not text:
        return jsonify({"error": "text_required"}), 400
    hours = max(1, min(hours, 720))
    now = datetime.utcnow()
    try:
        n = Note(
            text=text,
            timestamp=now,
            expires_at=now + timedelta(hours=hours),
            author_fp=_fingerprint_from_request(request),
        )
        db.session.add(n)
        db.session.commit()
        return jsonify({"id": n.id, "ok": True}), 201
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": "create_failed", "detail": str(e)}), 500

# Contadores básicos (opcionales, por compat)
@api.route("/notes/<int:note_id>/view", methods=["POST"])
def view_note(note_id: int):
    n = db.session.get(Note, note_id)
    if not n:
        return jsonify({"error": "not_found"}), 404
    n.views = (n.views or 0) + 1
    db.session.commit()
    return jsonify({"ok": True, "views": n.views})

@api.route("/notes/<int:note_id>/like", methods=["POST"])
def like_note(note_id: int):
    n = db.session.get(Note, note_id)
    if not n:
        return jsonify({"error": "not_found"}), 404
    n.likes = (n.likes or 0) + 1
    db.session.commit()
    return jsonify({"ok": True, "likes": n.likes})

@api.route("/notes/<int:note_id>/report", methods=["POST"])
def report_note(note_id: int):
    n = db.session.get(Note, note_id)
    if not n:
        return jsonify({"error": "not_found"}), 404
    n.reports = (n.reports or 0) + 1
    db.session.commit()
    return jsonify({"ok": True, "reports": n.reports})
PYCODE

# Reinicio limpio y smoke
pkill -f "python .*run\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "flask" 2>/dev/null || true
sleep 1

nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 3

echo ">>> URL MAP"
python - <<'PY'
from run import app
for r in sorted(app.url_map.iter_rules(), key=lambda r: r.rule):
    if "/api" in r.rule:
        print(f" {r.rule:28s} {sorted(list(r.methods))} {r.endpoint}")
PY

echo ">>> SMOKES"
curl -sS -o /dev/null -w "health=%{http_code}\n"      "http://127.0.0.1:8000/api/health"
curl -sS -o /dev/null -w "notes_get=%{http_code}\n"   "http://127.0.0.1:8000/api/notes"
curl -sS -o /dev/null -w "notes_post=%{http_code}\n"  -H "Content-Type: application/json" -d '{"text":"nota clean reset","hours":24}' "http://127.0.0.1:8000/api/notes"
