#!/usr/bin/env bash
set -Eeuo pipefail

ROUTES="backend/routes.py"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
TMPDIR="${TMPDIR:-$PREFIX/tmp}"
LOG="${TMPDIR}/paste12_server.log"
SERVER="http://127.0.0.1:8000"

mkdir -p "$TMPDIR"
cp -f "$ROUTES" "$ROUTES.bak.$(date +%s)"

python - <<'PY'
from pathlib import Path
import re

p = Path("backend/routes.py")
s = p.read_text(encoding="utf-8")

# Inserta un serializer simple si falta
if "_note_to_dict(" not in s:
    s += """

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
"""

# Reemplaza completamente list_notes (paginado seguro)
pattern_list = r"def\s+list_notes\s*\([^)]*\):[\s\S]*?(?=\ndef\s+\w+\s*\(|\Z)"
repl_list = '''def list_notes():
    from flask import request, jsonify
    try:
        page = int((request.args.get("page") or "1").strip() or "1")
    except Exception:
        page = 1
    if page < 1:
        page = 1
    q = db.session.query(Note).order_by(Note.id.desc())
    items = q.limit(20).offset((page - 1) * 20).all()
    return jsonify([_note_to_dict(n) for n in items])
'''
s = re.sub(pattern_list, repl_list, s, flags=re.S)

# Reemplaza completamente create_note (JSON robusto + author_fp server-side)
pattern_create = r"def\s+create_note\s*\([^)]*\):[\s\S]*?(?=\ndef\s+\w+\s*\(|\Z)"
repl_create = '''def create_note():
    from flask import request, jsonify
    from datetime import datetime, timedelta
    data = request.get_json(silent=True) or {}
    text = (data.get("text") or "").strip()
    try:
        hours = int(data.get("hours") or 24)
    except Exception:
        hours = 24
    if not text:
        return jsonify({"error":"text_required"}), 400
    hours = max(1, min(hours, 720))
    now = datetime.utcnow()
    n = Note(
        text=text,
        timestamp=now,
        expires_at=now + timedelta(hours=hours),
        author_fp=_fingerprint_from_request(request)
    )
    db.session.add(n)
    db.session.commit()
    return jsonify({"id": n.id, "ok": True})
'''
s = re.sub(pattern_create, repl_create, s, flags=re.S)

# Asegura imports clave presentes (sin romper los from __future__)
if "from backend import db" not in s:
    s = s.replace("from hashlib import sha256", "from hashlib import sha256\nfrom backend import db")
if "from backend.models import Note" not in s:
    s = s.replace("from backend import db", "from backend import db\nfrom backend.models import Note")

p.write_text(s, encoding="utf-8")
print("routes.py handlers parcheados correctamente.")
PY

# Reinicio limpio
pkill -f "python .*run\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "flask" 2>/dev/null || true
sleep 1

nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 2

# Smokes
curl -sS -o /dev/null -w "health=%{http_code}\n" "$SERVER/api/health"
curl -sS -o /dev/null -w "notes_get=%{http_code}\n" "$SERVER/api/notes"
curl -sS -o /dev/null -w "notes_post=%{http_code}\n" -H "Content-Type: application/json" -d '{"text":"nota estable v2","hours":24}' "$SERVER/api/notes"
