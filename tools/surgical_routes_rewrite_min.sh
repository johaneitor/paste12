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

# --- 1) Futuro al tope + imports obligatorios ---
lines = s.splitlines()
i=0
hdr=[]
def is_hdr(l):
    t=l.strip(); return (t=="" or t.startswith("#") or t.startswith("#!") or t.startswith("# -*-"))
while i<len(lines) and is_hdr(lines[i]):
    hdr.append(lines[i]); i+=1
doc=[]
if i<len(lines) and lines[i].lstrip().startswith(('"""',"'''")):
    q=lines[i].lstrip()[:3]; doc.append(lines[i]); i+=1
    while i<len(lines):
        doc.append(lines[i]); 
        if lines[i].strip().endswith(q): i+=1; break
body=lines[i:]

futures=[]; rest=[]
for ln in body:
    if ln.startswith("from __future__ import"):
        if ln not in futures: futures.append(ln)
    else:
        rest.append(ln)

# limpiar imports que vamos a reinsertar
kill = {
    "from hashlib import sha256",
    "from backend import db",
    "from backend.models import Note",
    "from flask import Blueprint, request, jsonify",
}
rest = [ln for ln in rest if ln.strip() not in kill]

out=[]
out+=hdr; out+=doc; out+=futures
if futures: out.append("")
out.append("from hashlib import sha256")
out.append("from flask import Blueprint, request, jsonify")
out.append("from backend import db")
out.append("from backend.models import Note")

# --- 2) Asegurar Blueprint 'bp' con name 'api' y url_prefix '/api' ---
txt="\n".join(out+rest)
if not re.search(r'\bBlueprint\(\s*[\'"]api[\'"]', txt):
    out.append("bp = Blueprint('api', __name__, url_prefix='/api')")
    txt="\n".join(out+rest)

# --- 3) Serializer si falta ---
if "_note_to_dict(" not in txt:
    txt += """

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

# --- 4) Reescribir list_notes y create_note con decoradores correctos ---
bp_var = re.search(r'(\w+)\s*=\s*Blueprint\(\s*[\'"]api[\'"]', txt)
bp_name = bp_var.group(1) if bp_var else "bp"

def repl_list(_):
    return f"""@{bp_name}.route("/notes", methods=["GET"])
def list_notes():
    try:
        page = int((request.args.get("page") or "1").strip() or "1")
    except Exception:
        page = 1
    if page < 1:
        page = 1
    stmt = db.select(Note).order_by(Note.id.desc()).limit(20).offset((page-1)*20)
    items = db.session.execute(stmt).scalars().all()
    return jsonify([_note_to_dict(n) for n in items])
"""

def repl_create(_):
    return f"""@{bp_name}.route("/notes", methods=["POST"])
def create_note():
    from datetime import datetime, timedelta
    data = request.get_json(silent=True) or {{}}
    text = (data.get("text") or "").strip()
    try:
        hours = int(data.get("hours") or 24)
    except Exception:
        hours = 24
    if not text:
        return jsonify({{"error":"text_required"}}), 400
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
    return jsonify({{"id": n.id, "ok": True}}), 201
"""

# reemplaza bloques existentes (si existen); si no, agrega al final
changed = False
txt2, n1 = re.subn(r'@.*?\n\s*def\s+list_notes\s*\([^)]*\):[\s\S]*?(?=\n@|\Z)', repl_list, txt, flags=re.S)
txt = txt2; changed = changed or n1>0
txt2, n2 = re.subn(r'@.*?\n\s*def\s+create_note\s*\([^)]*\):[\s\S]*?(?=\n@|\Z)', repl_create, txt, flags=re.S)
txt = txt2; changed = changed or n2>0
if not changed:
    # si no encontró nada, añadimos ambos al final
    txt += "\n\n" + repl_list(None) + "\n" + repl_create(None)

Path("backend/routes.py").write_text(txt, encoding="utf-8")
print("routes.py saneado (Blueprint + handlers reescritos)")
PY

# restart limpio
pkill -f "python .*run\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "flask" 2>/dev/null || true
sleep 1
nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 2

# smokes + mapa
echo ">>> SMOKES"
curl -sS -o /dev/null -w "health=%{http_code}\n" "$SERVER/api/health"
curl -sS -o /dev/null -w "notes_get=%{http_code}\n" "$SERVER/api/notes"
curl -sS -o /dev/null -w "notes_post=%{http_code}\n" -H "Content-Type: application/json" -d '{"text":"nota FINAL","hours":24}' "$SERVER/api/notes"

python - <<'PY'
from run import app
print(">>> URL MAP (parcial):")
for r in app.url_map.iter_rules():
    if "/api" in r.rule or "notes" in r.rule or "health" in r.rule:
        print(f" {r.rule:28s} {sorted(list(r.methods))} {r.endpoint}")
PY

echo "Log: $LOG (tail -n 160 \"$LOG\")"
