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
from pathlib import Path, re
p = Path("backend/routes.py")
s = p.read_text(encoding="utf-8")

# Asegurar imports clave (sin romper los from __future__ al tope)
def ensure_import(code, needle, insert_after):
    if needle in code:
        return code
    return code.replace(insert_after, insert_after + "\n" + needle)

if "from backend import db" not in s:
    s = s.replace("from hashlib import sha256", "from hashlib import sha256\nfrom backend import db")
if "from backend.models import Note" not in s:
    s = s.replace("from backend import db", "from backend import db\nfrom backend.models import Note")

# Reemplazar list_notes para usar query() clásico (más compatible)
pat_list = r"@.*\n\s*def\s+list_notes\s*\([^)]*\):[\s\S]*?(?=\n@|\Z)"
new_list = '''@api.route("/notes", methods=["GET"])
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
'''
s = re.sub(pat_list, new_list, s, flags=re.S)

# Reemplazar create_note con manejo de errores + rollback
pat_create = r"@.*\n\s*def\s+create_note\s*\([^)]*\):[\s\S]*?(?=\n@|\Z)"
new_create = '''@api.route("/notes", methods=["POST"])
def create_note():
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
    try:
        n = Note(
            text=text,
            timestamp=now,
            expires_at=now + timedelta(hours=hours),
            author_fp=_fingerprint_from_request(request)
        )
        db.session.add(n)
        db.session.commit()
        return jsonify({"id": n.id, "ok": True}), 201
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": "create_failed", "detail": str(e)}), 500
'''
s = re.sub(pat_create, new_create, s, flags=re.S)

Path("backend/routes.py").write_text(s, encoding="utf-8")
print("routes.py parcheado (query() clásico + rollback en POST).")
PY

# Reinicio limpio
pkill -f "python .*run\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "flask" 2>/dev/null || true
sleep 1

nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 3

# Smokes
echo ">>> SMOKES"
curl -sS -o /dev/null -w "health=%{http_code}\n" "$SERVER/api/health"
curl -sS -o /dev/null -w "notes_get=%{http_code}\n" "$SERVER/api/notes"
curl -sS -o /dev/null -w "notes_post=%{http_code}\n" -H "Content-Type: application/json" -d '{"text":"nota estable SA1","hours":24}' "$SERVER/api/notes"

# Si algo falla, mostrar últimas líneas del log y un SELECT directo para ver que la tabla existe
if [ $? -ne 0 ]; then
  tail -n 160 "$LOG" || true
fi
