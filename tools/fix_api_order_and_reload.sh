#!/usr/bin/env bash
set -Eeuo pipefail
ROUTES="backend/routes.py"
RUNPY="run.py"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
TMPDIR="${TMPDIR:-$PREFIX/tmp}"
LOG="${TMPDIR}/paste12_server.log"
SERVER="http://127.0.0.1:8000"

mkdir -p "$TMPDIR"
cp -f "$ROUTES" "$ROUTES.bak.$(date +%s)" 2>/dev/null || true

python - <<'PY'
from pathlib import Path, re
p = Path("backend/routes.py")
src = p.read_text(encoding="utf-8").splitlines()

# --- 1) Separar cabecera/docstring para poder poner futuros al tope ---
i = 0
head = []
def is_head(l):
    s=l.strip(); return s=="" or s.startswith("#") or s.startswith("#!") or s.startswith("# -*-")
while i < len(src) and is_head(src[i]):
    head.append(src[i]); i += 1

doc = []
if i < len(src) and src[i].lstrip().startswith(('"""',"'''")):
    q = src[i].lstrip()[:3]
    doc.append(src[i]); i += 1
    while i < len(src):
        doc.append(src[i])
        if src[i].strip().endswith(q):
            i += 1; break

body = src[i:]

# --- 2) Extraer futuros e imports; limpiaremos y reinsertaremos en orden ---
futures, rest = [], []
for ln in body:
    if ln.startswith("from __future__ import"):
        if ln not in futures: futures.append(ln)
    else:
        rest.append(ln)

# elimina imports que vamos a reinsertar
kill = {
    "from hashlib import sha256",
    "from flask import Blueprint, request, jsonify",
    "from backend import db",
    "from backend.models import Note",
}
rest = [ln for ln in rest if ln.strip() not in kill]

# reconstruye encabezado + futuros + imports MINIMOS
out = []
out += head
out += doc
out += futures
if futures: out.append("")
out += [
    "from hashlib import sha256",
    "from flask import Blueprint, request, jsonify",
    "from backend import db",
    "from backend.models import Note",
]

# --- 3) Cuerpo limpio (sin definir aún el blueprint), para ubicar dónde insertarlo ---
body2 = rest[:]

# Busca si ya hay alguna definición de api o bp
has_api_def = any(re.match(r'\s*api\s*=\s*Blueprint\(', ln) for ln in body2)
has_bp_def  = any(re.match(r'\s*bp\s*=\s*Blueprint\(', ln) for ln in body2)

# Índice del primer decorador en body2
first_deco_idx = None
for idx, ln in enumerate(body2):
    if ln.lstrip().startswith('@'):
        first_deco_idx = idx
        break
if first_deco_idx is None:
    first_deco_idx = 0  # no hay decoradores; insertaremos al principio del body

# Insertar la definición del blueprint ANTES del primer decorador
ins = []
if has_api_def:
    # ya existe 'api = Blueprint(...)' en el file, lo dejamos; sólo aseguramos que esté antes
    # Si estaba después del primer decorador, lo movemos aquí: sacarlo y reinsertarlo arriba.
    new_body = []
    moved = False
    for ln in body2:
        if not moved and re.match(r'\s*api\s*=\s*Blueprint\(', ln):
            ins.append(ln)
            moved = True
        else:
            new_body.append(ln)
    body2 = new_body
elif has_bp_def:
    # existe 'bp = Blueprint(...)'; creamos alias api = bp
    # también movemos la definición de bp antes de los decoradores si estaba abajo
    new_body = []
    moved_bp = False
    for ln in body2:
        if not moved_bp and re.match(r'\s*bp\s*=\s*Blueprint\(', ln):
            ins.append(ln)
            moved_bp = True
        else:
            new_body.append(ln)
    body2 = new_body
    ins.append("api = bp")
else:
    # no hay ninguno: creamos api directo
    ins.append("api = Blueprint('api', __name__, url_prefix='/api')")

# Inserta INS antes del primer decorador
body2 = body2[:first_deco_idx] + ins + [""] + body2[first_deco_idx:]

# --- 4) Asegurar helper fingerprint y serializer (si faltan) ---
txt = "\n".join(out + body2)

if "_fingerprint_from_request" not in txt:
    txt += """

def _fingerprint_from_request(req):
    ip = (req.headers.get("X-Forwarded-For") or getattr(req, "remote_addr", "") or "").split(",")[0].strip()
    ua = req.headers.get("User-Agent", "")
    raw = f"{ip}|{ua}"
    return sha256(raw.encode("utf-8")).hexdigest()
"""

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

# --- 5) Asegurar health/list/create con @api.route ---
def ensure_block(text, pat, block):
    if not re.search(pat, text, flags=re.S):
        text += "\n\n" + block.strip() + "\n"
    return text

txt = ensure_block(txt, r'@.*\.\s*route\(\s*["\']/health["\'].*\)\s*\ndef\s+health\s*\(', """
@api.route("/health", methods=["GET"])
def health():
    return jsonify({"ok": True})
""")

txt = ensure_block(txt, r'@.*\.\s*route\(\s*["\']/notes["\'].*GET.*\)\s*\ndef\s+list_notes\s*\(', """
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
""")

txt = ensure_block(txt, r'@.*\.\s*route\(\s*["\']/notes["\'].*POST.*\)\s*\ndef\s+create_note\s*\(', """
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
""")

p.write_text(txt, encoding="utf-8")
print("routes.py: blueprint 'api' DEFINIDO antes de decoradores y handlers OK.")
PY

# Reinicio limpio
pkill -f "python .*run\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "flask" 2>/dev/null || true
sleep 1

nohup python "$RUNPY" >"$LOG" 2>&1 & disown || true
sleep 3

echo ">>> URL MAP (parcial)"
python - <<'PY'
from run import app
for r in sorted(app.url_map.iter_rules(), key=lambda r: r.rule):
    if "/api" in r.rule or "notes" in r.rule or "health" in r.rule:
        print(f" {r.rule:28s} {sorted(list(r.methods))} {r.endpoint}")
PY

echo ">>> SMOKES"
curl -sS -o /dev/null -w "health=%{http_code}\n" "$SERVER/api/health"
curl -sS -o /dev/null -w "notes_get=%{http_code}\n" "$SERVER/api/notes"
curl -sS -o /dev/null -w "notes_post=%{http_code}\n" -H "Content-Type: application/json" -d '{"text":"nota OK FIN","hours":24}' "$SERVER/api/notes"

echo "Log: $LOG (tail -n 200 \"$LOG\")"
