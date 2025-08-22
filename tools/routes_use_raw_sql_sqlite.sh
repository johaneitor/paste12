#!/usr/bin/env bash
set -Eeuo pipefail
ROUTES="backend/routes.py"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
TMPDIR="${TMPDIR:-$PREFIX/tmp}"
LOG="${TMPDIR}/paste12_server.log"
SERVER="http://127.0.0.1:8000"

cp -f "$ROUTES" "$ROUTES.bak.$(date +%s)" 2>/dev/null || true

python - <<'PY'
from pathlib import Path, re
p = Path("backend/routes.py")
s = p.read_text(encoding="utf-8")

# Asegurar import de text() para SQL crudo
if "from sqlalchemy import text as _sql_text" not in s:
    # Insertar tras imports de flask/backend/models
    lines = s.splitlines()
    ins_idx = 0
    for i, ln in enumerate(lines):
        if "from backend.models import Note" in ln or "from backend import db" in ln or "from flask import" in ln:
            ins_idx = i
    lines.insert(ins_idx+1, "from sqlalchemy import text as _sql_text")
    s = "\n".join(lines)

# Reemplazar list_notes
pat_list = r"@.*\n\s*def\s+list_notes\s*\([^)]*\):[\s\S]*?(?=\n@|\Z)"
new_list = '''@api.route("/notes", methods=["GET"])
def list_notes():
    from flask import request, jsonify
    try:
        page = int((request.args.get("page") or "1").strip() or "1")
    except Exception:
        page = 1
    if page < 1:
        page = 1
    limit = 20
    offset = (page - 1) * limit
    rows = db.session.execute(_sql_text(
        "SELECT id, text, timestamp, expires_at, likes, views, reports "
        "FROM notes ORDER BY id DESC LIMIT :limit OFFSET :offset"
    ), {"limit": limit, "offset": offset}).fetchall()
    def _row_to_dict(r):
        # r es Row; acceder por índice o clave
        d = dict(r._mapping) if hasattr(r, "_mapping") else dict(r)
        # Normalizar a tipos serializables (sqlite trae strings para datetimes)
        return {
            "id": d.get("id"),
            "text": d.get("text"),
            "timestamp": d.get("timestamp"),
            "expires_at": d.get("expires_at"),
            "likes": d.get("likes") or 0,
            "views": d.get("views") or 0,
            "reports": d.get("reports") or 0,
        }
    return jsonify([_row_to_dict(r) for r in rows])
'''
s = re.sub(pat_list, new_list, s, flags=re.S)

# Reemplazar create_note
pat_create = r"@.*\n\s*def\s+create_note\s*\([^)]*\):[\s\S]*?(?=\n@|\Z)"
new_create = '''@api.route("/notes", methods=["POST"])
def create_note():
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
    try:
        params = {
            "text": text,
            "ts": now.isoformat(sep=" "),
            "exp": (now + timedelta(hours=hours)).isoformat(sep=" "),
            "fp": _fingerprint_from_request(request),
        }
        db.session.execute(_sql_text(
            "INSERT INTO notes (text, timestamp, expires_at, likes, views, reports, author_fp) "
            "VALUES (:text, :ts, :exp, 0, 0, 0, :fp)"
        ), params)
        # obtener id de sqlite
        new_id = db.session.execute(_sql_text("SELECT last_insert_rowid()")).scalar()
        db.session.commit()
        return jsonify({"id": int(new_id), "ok": True}), 201
    except Exception as e:
        db.session.rollback()
        return jsonify({"error":"create_failed", "detail": str(e)}), 500
'''
s = re.sub(pat_create, new_create, s, flags=re.S)

p.write_text(s, encoding="utf-8")
print("routes.py actualizado para usar SQL crudo en GET/POST /api/notes")
PY

# Reinicio y smokes
pkill -f "python .*run\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "flask" 2>/dev/null || true
sleep 1

nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 3

echo ">>> SMOKES"
curl -sS -o /dev/null -w "health=%{http_code}\n" "http://127.0.0.1:8000/api/health"
curl -sS -o /dev/null -w "notes_get=%{http_code}\n" "http://127.0.0.1:8000/api/notes"
curl -sS -o /dev/null -w "notes_post=%{http_code}\n" -H "Content-Type: application/json" -d '{"text":"nota via SQL crudo","hours":24}' "http://127.0.0.1:8000/api/notes"

echo "Log: $LOG (tail -n 200 \"$LOG\")"
