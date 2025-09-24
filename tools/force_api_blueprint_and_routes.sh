#!/usr/bin/env bash
set -Eeuo pipefail
REPO="$(pwd)"
ROUTES="$REPO/backend/routes.py"
RUNPY="$REPO/run.py"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
TMPDIR="${TMPDIR:-$PREFIX/tmp}"
LOG="${TMPDIR}/paste12_server.log"
SERVER="http://127.0.0.1:8000"

mkdir -p "$TMPDIR"
cp -f "$ROUTES" "$ROUTES.bak.$(date +%s)" 2>/dev/null || true
cp -f "$RUNPY"  "$RUNPY.bak.$(date +%s)"  2>/dev/null || true

echo "➤ Normalizando routes.py (futuros + imports + blueprint + handlers)"
python - <<'PY'
from pathlib import Path
import re
p = Path("backend/routes.py")
txt = p.read_text(encoding="utf-8")

# 1) Mover todos los from __future__ al tope (respetar docstring)
lines = txt.splitlines()
i=0; head=[]
def is_head(l):
    s=l.strip(); return s=="" or s.startswith("#") or s.startswith("#!") or s.startswith("# -*-")
while i<len(lines) and is_head(lines[i]): head.append(lines[i]); i+=1
doc=[]
if i<len(lines) and lines[i].lstrip().startswith(('"""',"'''")):
    q=lines[i].lstrip()[:3]; doc.append(lines[i]); i+=1
    while i<len(lines):
        doc.append(lines[i])
        if lines[i].strip().endswith(q): i+=1; break
body=lines[i:]
futures=[]; rest=[]
for ln in body:
    if ln.startswith("from __future__ import"):
        if ln not in futures: futures.append(ln)
    else:
        rest.append(ln)

kill = {
    "from hashlib import sha256",
    "from flask import Blueprint, request, jsonify",
    "from backend import db",
    "from backend.models import Note",
}
rest = [ln for ln in rest if ln.strip() not in kill]

out=[]
out+=head; out+=doc; out+=futures
if futures: out.append("")
out.append("from hashlib import sha256")
out.append("from flask import Blueprint, request, jsonify")
out.append("from backend import db")
out.append("from backend.models import Note")

txt = "\n".join(out + rest)

# 2) Blueprint api garantizado (y alias si hubiera bp)
if not re.search(r'\b\w+\s*=\s*Blueprint\(\s*[\'"]api[\'"]', txt):
    txt += "\n\napi = Blueprint('api', __name__, url_prefix='/api')\n"
if re.search(r'\bbp\s*=\s*Blueprint\(\s*[\'"]api[\'"]', txt) and not re.search(r'\napi\s*=', txt):
    txt += "\n# alias compat\napi = bp\n"

# 3) Helper fingerprint (si falta)
if "_fingerprint_from_request" not in txt:
    txt += """

def _fingerprint_from_request(req):
    ip = (req.headers.get("X-Forwarded-For") or getattr(req, "remote_addr", "") or "").split(",")[0].strip()
    ua = req.headers.get("User-Agent", "")
    raw = f"{ip}|{ua}"
    return sha256(raw.encode("utf-8")).hexdigest()
"""

# 4) Serializer (si falta)
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

# 5) Handlers básicos y robustos (health, list, create) con @api.route
def ensure_block(text, pat, block):
    if not re.search(pat, text, flags=re.S):
        text += "\n\n" + block.strip() + "\n"
    else:
        # Reemplazo para sanear si existe
        text = re.sub(pat, block.strip(), text, flags=re.S, count=1)
    return text

health_pat = r'@.*\.\s*route\(\s*["\']\/health["\'].*\)\s*\ndef\s+health\s*\(.*?\)\s*:[\s\S]*?(?=\n@|\Z)'
health_blk = '''
@api.route("/health", methods=["GET"])
def health():
    return jsonify({"ok": True})
'''

list_pat = r'@.*\.\s*route\(\s*["\']\/notes["\'].*GET.*\)\s*\ndef\s+list_notes\s*\(.*?\)\s*:[\s\S]*?(?=\n@|\Z)'
list_blk = '''
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
'''

create_pat = r'@.*\.\s*route\(\s*["\']\/notes["\'].*POST.*\)\s*\ndef\s+create_note\s*\(.*?\)\s*:[\s\S]*?(?=\n@|\Z)'
create_blk = '''
@api.route("/notes", methods=["POST"])
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
        return jsonify({"error":"create_failed","detail":str(e)}), 500
'''

txt = ensure_block(txt, health_pat, health_blk)
txt = ensure_block(txt, list_pat,   list_blk)
txt = ensure_block(txt, create_pat, create_blk)

Path("backend/routes.py").write_text(txt, encoding="utf-8")
print("routes.py OK")
PY

echo "➤ Asegurando registro del blueprint en run.py justo tras crear app"
python - <<'PY'
from pathlib import Path, re
p = Path("run.py")
s = p.read_text(encoding="utf-8")
# localizar app = Flask(...)
m = re.search(r'app\s*=\s*Flask\([^\)]*\)', s)
if not m:
    raise SystemExit("No encontré 'app = Flask(...)' en run.py")
insert_pos = m.end()

snippet = '''
# --- Auto-register API blueprint ---
try:
    from backend.routes import api as api_blueprint
except Exception as e:
    print("No pude importar backend.routes:", e)
else:
    if "api" not in app.blueprints:
        app.register_blueprint(api_blueprint)
# -----------------------------------
'''

# Insertar el snippet si no existe ya
if 'register_blueprint(api_blueprint)' not in s:
    s = s[:insert_pos] + "\n" + snippet + s[insert_pos:]

p.write_text(s, encoding="utf-8")
print("run.py OK (registro blueprint)")
PY

echo "➤ Restart limpio"
pkill -f "python .*run\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "flask" 2>/dev/null || true
sleep 1
nohup python "$RUNPY" >"$LOG" 2>&1 & disown || true
sleep 3

echo "➤ URL map parcial"
python - <<'PY'
from run import app
rules = []
for r in app.url_map.iter_rules():
    if "/api" in r.rule or "notes" in r.rule or "health" in r.rule:
        rules.append((r.rule, sorted(list(r.methods)), r.endpoint))
for rule, methods, ep in sorted(rules):
    print(f" {rule:28s} {methods} {ep}")
PY

echo "➤ Smokes"
curl -sS -o /dev/null -w "health=%{http_code}\n" "$SERVER/api/health"
curl -sS -o /dev/null -w "notes_get=%{http_code}\n" "$SERVER/api/notes"
curl -sS -o /dev/null -w "notes_post=%{http_code}\n" -H "Content-Type: application/json" -d '{"text":"nota FINAL estable","hours":24}' "$SERVER/api/notes"

echo "ℹ️ Log: $LOG  (tail -n 200 \"$LOG\")"
