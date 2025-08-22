#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(pwd)"
ROUTES="${REPO_ROOT}/backend/routes.py"
BACKEND_DIR="${REPO_ROOT}/backend"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
TMPDIR="${TMPDIR:-$PREFIX/tmp}"
LOG="${TMPDIR}/paste12_server.log"
SERVER="http://127.0.0.1:8000"

mkdir -p "$TMPDIR"
cp -f "$ROUTES" "$ROUTES.bak.$(date +%s)"

echo "➤ Normalizando encabezado e imports en routes.py"
python - <<'PY'
from pathlib import Path
p = Path("backend/routes.py")
lines = p.read_text(encoding="utf-8").splitlines()

# 1) separar encabezado/comment/docstring
i = 0
head = []
def is_head(l):
    s = l.strip()
    return s=="" or s.startswith("#") or s.startswith("#!") or s.startswith("# -*-")
while i < len(lines) and is_head(lines[i]):
    head.append(lines[i]); i += 1

doc = []
if i < len(lines) and lines[i].lstrip().startswith(('"""',"'''")):
    q = lines[i].lstrip()[:3]
    doc.append(lines[i]); i += 1
    while i < len(lines):
        doc.append(lines[i])
        if lines[i].strip().endswith(q):
            i += 1; break

body = lines[i:]

# 2) extraer futuros; limpiar imports conflictivos
futures, rest = [], []
for ln in body:
    if ln.startswith("from __future__ import"):
        if ln not in futures: futures.append(ln)
    else:
        rest.append(ln)

# quitar duplicados que vamos a reinsertar en lugar correcto
rest = [ln for ln in rest if ln.strip() != "from hashlib import sha256"]
rest = [ln for ln in rest if ln.strip() != "from backend.models import Note"]
rest = [ln for ln in rest if ln.strip() != "from backend import db"]

out = []
out.extend(head)
out.extend(doc)
out.extend(futures)
if futures: out.append("")
# imports obligatorios inmediatamente después de los futuros
out.append("from hashlib import sha256")
out.append("from backend import db")
out.append("from backend.models import Note")
# unir con el resto
out.extend(rest)

p.write_text("\n".join(out) + "\n", encoding="utf-8")
print("Routes: encabezado normalizado e imports reubicados.")
PY

echo "➤ Parcheando handlers list_notes y create_note"
python - <<'PY'
from pathlib import Path, re
p = Path("backend/routes.py")
s = p.read_text(encoding="utf-8")

# Helper serializer (si no existe)
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

# list_notes robusto
s = re.sub(
    r"def\s+list_notes\s*\([^)]*\):[\s\S]*?return\s+[^\n]+",
    """def list_notes():
    from flask import request, jsonify
    try:
        page = int((request.args.get("page") or "1").strip() or "1")
    except Exception:
        page = 1
    page = 1 if page < 1 else page
    q = db.session.query(Note).order_by(Note.id.desc())
    items = q.limit(20).offset((page - 1) * 20).all()
    return jsonify([_note_to_dict(n) for n in items])""",
    count=1
)

# create_note robusto (parse JSON, default hours, author_fp server-side)
s = re.sub(
    r"def\s+create_note\s*\([^)]*\):[\s\S]*?return\s+[^\n]+",
    """def create_note():
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
    return jsonify({"id": n.id, "ok": True})""",
    count=1
)

# Asegurar que endpoints usen db.session (no otra Session)
s = s.replace("Session(", "db.session")  # por si había Session() suelta

# Guardar
p.write_text(s, encoding="utf-8")
print("Handlers list/create parcheados.")
PY

echo "➤ Reinicio limpio"
pkill -f "python .*run\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "flask" 2>/dev/null || true
sleep 1

echo "➤ Arrancando servidor"
nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 2

echo "➤ Smokes"
curl -sS -o /dev/null -w "health=%{http_code}\n" "$SERVER/api/health"
curl -sS -o /dev/null -w "notes_get=%{http_code}\n" "$SERVER/api/notes"
curl -sS -o /dev/null -w "notes_post=%{http_code}\n" -H "Content-Type: application/json" -d '{"text":"nota estable","hours":24}' "$SERVER/api/notes"

echo "➤ Mapper/columns de Note (comprobación rápida)"
python - <<'PY'
from run import app
from backend.models import Note
with app.app_context():
    print("Note mapped cols:", [c.name for c in Note.__table__.columns])
PY

echo "ℹ️ Si algo falla, tail -n 200 \"$LOG\""
