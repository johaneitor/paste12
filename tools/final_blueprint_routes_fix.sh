#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(pwd)"
ROUTES="${REPO_ROOT}/backend/routes.py"
RUNFILE="${REPO_ROOT}/run.py"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
TMPDIR="${TMPDIR:-$PREFIX/tmp}"
LOG="${TMPDIR}/paste12_server.log"
SERVER="http://127.0.0.1:8000"

mkdir -p "$TMPDIR"
cp -f "$ROUTES" "$ROUTES.bak.$(date +%s)" 2>/dev/null || true
cp -f "$RUNFILE" "$RUNFILE.bak.$(date +%s)" 2>/dev/null || true

echo "➤ Normalizando backend/routes.py"
python - <<'PY'
from pathlib import Path
import re
p = Path("backend/routes.py")
s = p.read_text(encoding="utf-8").splitlines()

# 1) encabezado y docstring (para dejar futuros arriba)
i = 0
head = []
def is_head(l):
    t = l.strip()
    return t=="" or t.startswith("#") or t.startswith("#!") or t.startswith("# -*-")
while i < len(s) and is_head(s[i]):
    head.append(s[i]); i += 1

doc = []
if i < len(s) and s[i].lstrip().startswith(('"""',"'''")):
    q = s[i].lstrip()[:3]
    doc.append(s[i]); i += 1
    while i < len(s):
        doc.append(s[i])
        if s[i].strip().endswith(q):
            i += 1; break

body = s[i:]

# 2) extraer futuros; limpiar imports que reinsertaremos
futures, rest = [], []
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

out = []
out.extend(head); out.extend(doc); out.extend(futures)
if futures: out.append("")
out.append("from hashlib import sha256")
out.append("from flask import Blueprint, request, jsonify")
out.append("from backend import db")
out.append("from backend.models import Note")

txt = "\n".join(out + rest)

# 3) asegurar blueprint 'api' usable
if not re.search(r'\bBlueprint\(\s*[\'"]api[\'"]', txt):
    # Si hay 'bp = Blueprint("api",...)' OK; si no, creamos api
    if not re.search(r'\b\w+\s*=\s*Blueprint\(\s*[\'"]api[\'"]', txt):
        txt += "\n\napi = Blueprint('api', __name__, url_prefix='/api')\n"

# si existe bp pero no api, agrega alias
if re.search(r'\bbp\s*=\s*Blueprint\(\s*[\'"]api[\'"]', txt) and not re.search(r'\napi\s*=', txt):
    txt += "\n# alias por compatibilidad\napi = bp\n"

# 4) helper fingerprint (si falta)
if "_fingerprint_from_request" not in txt:
    txt += """

def _fingerprint_from_request(req):
    ip = (req.headers.get("X-Forwarded-For") or getattr(req, "remote_addr", "") or "").split(",")[0].strip()
    ua = req.headers.get("User-Agent", "")
    raw = f"{ip}|{ua}"
    return sha256(raw.encode("utf-8")).hexdigest()
"""

# 5) serializer (si falta)
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

# 6) asegurar /api/health GET
if not re.search(r'@.*\.\s*route\(\s*["\']\/health["\'].*\)\s*\ndef\s+health\s*\(', txt):
    txt += """

@api.route("/health", methods=["GET"])
def health():
    return jsonify({"ok": True})
"""

# 7) asegurar /api/notes GET
if not re.search(r'@.*\.\s*route\(\s*["\']\/notes["\'].*GET.*\)\s*\ndef\s+list_notes\s*\(', txt, flags=re.S):
    txt += """

@api.route("/notes", methods=["GET"])
def list_notes():
    try:
        page = int((request.args.get("page") or "1").strip() or "1")
    except Exception:
        page = 1
    if page < 1:
        page = 1
    # SQLAlchemy 2.0 style select
    stmt = db.select(Note).order_by(Note.id.desc()).limit(20).offset((page-1)*20)
    items = db.session.execute(stmt).scalars().all()
    return jsonify([_note_to_dict(n) for n in items])
"""

# 8) asegurar /api/notes POST
if not re.search(r'@.*\.\s*route\(\s*["\']\/notes["\'].*POST.*\)\s*\ndef\s+create_note\s*\(', txt, flags=re.S):
    txt += """

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
    n = Note(
        text=text,
        timestamp=now,
        expires_at=now + timedelta(hours=hours),
        author_fp=_fingerprint_from_request(request)
    )
    db.session.add(n)
    db.session.commit()
    return jsonify({"id": n.id, "ok": True}), 201
"""

Path("backend/routes.py").write_text(txt, encoding="utf-8")
print("routes.py normalizado y handlers asegurados.")
PY

echo "➤ Asegurando registro del blueprint en run.py (sin duplicar)"
python - <<'PY'
from pathlib import Path
import re, importlib
p = Path("run.py")
s = p.read_text(encoding="utf-8")

# Inserta helper de registro robusto si no está
if "register_api_blueprint(" not in s:
    helper = '''
def register_api_blueprint(app):
    try:
        import importlib
        mod = importlib.import_module("backend.routes")
        api_bp = getattr(mod, "api", None) or getattr(mod, "bp", None)
        if api_bp and "api" not in app.blueprints:
            app.register_blueprint(api_bp)
    except Exception as e:
        print("No pude importar backend.routes:", e)
'''
    # Inserta tras las configuraciones de app
    s += "\n" + helper + "\nregister_api_blueprint(app)\n"

# Evitar doble registro (si ya estaba, este helper chequea app.blueprints)
Path("run.py").write_text(s, encoding="utf-8")
print("run.py listo con registro robusto del blueprint.")
PY

echo "➤ Reinicio limpio"
pkill -f "python .*run\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "flask" 2>/dev/null || true
sleep 1

echo "➤ Levantando servidor (log: $LOG)"
nohup python "$RUNFILE" >"$LOG" 2>&1 & disown || true
sleep 3

# Smokes y URL map
echo ">>> SMOKES"
curl -sS -o /dev/null -w "health=%{http_code}\n" "$SERVER/api/health"
curl -sS -o /dev/null -w "notes_get=%{http_code}\n" "$SERVER/api/notes"
curl -sS -o /dev/null -w "notes_post=%{http_code}\n" -H "Content-Type: application/json" -d '{"text":"nota FINAL OK","hours":24}' "$SERVER/api/notes"

python - <<'PY'
from run import app
print(">>> URL MAP (parcial):")
for r in app.url_map.iter_rules():
    if "/api" in r.rule or "notes" in r.rule or "health" in r.rule:
        print(f" {r.rule:28s} {sorted(list(r.methods))} {r.endpoint}")
PY

echo "ℹ️ Log: $LOG  (tail -n 200 \"$LOG\")"
