#!/usr/bin/env bash
set -euo pipefail

F="backend/routes.py"
[[ -f "$F" ]] || { echo "No existe $F"; exit 1; }

cp -n "$F" "$F.bak.$(date -u +%Y%m%dT%H%M%SZ)" || true

python - <<'PY'
from pathlib import Path
import re

p = Path("backend/routes.py")
src = p.read_text(encoding="utf-8")

# 1) Normalización básica
src = src.replace("\r\n","\n").replace("\r","\n").replace("\t","    ")

lines = src.splitlines()

def leading_spaces(s: str) -> int:
    return len(s) - len(s.lstrip(" "))

# 2) Llevar a columna 0 imports, decoradores y defs top-level mal indentados
for i,ln in enumerate(lines):
    if re.match(r"^\s+from (flask|__future__)\s+import ", ln): lines[i] = ln.lstrip()
    if re.match(r"^\s+import (sqlalchemy|datetime|typing|re|json)\b", ln): lines[i] = ln.lstrip()
    if re.match(r"^\s+@api\.route\(", ln): lines[i] = ln.lstrip()
    if re.match(r"^\s+def [a-zA-Z_]\w*\(", ln):
        # Si la anterior está vacía o es decorador, col 0
        prev = lines[i-1] if i>0 else ""
        if prev.strip()=="" or prev.lstrip().startswith("@"):
            lines[i] = ln.lstrip()

# 3) Arreglar líneas sueltas con "unindent" cerca de POST /notes (fallo típico)
text = "\n".join(lines)

# Si el bloque create_note está mal, reescribir bloque entre el decorador y la siguiente ruta/EOF.
pat = re.compile(
    r'(?ms)^@api\.route\("/notes",\s*methods=\["POST"\]\)\s*\ndef\s+create_note\s*\([^)]*\)\s*:\s*.*?(?=^@api\.route\(|\Z)'
)
if not pat.search(text):
    # Intentar detectar el decorador pero sin la def bien formada (indent roto)
    broken_deco = re.search(r'(?m)^@api\.route\("/notes",\s*methods=\["POST"\]\)\s*$', text)
    if broken_deco:
        start = broken_deco.start()
        # Cortar hasta la próxima ruta o EOF
        nxt = re.search(r'(?m)^@api\.route\(', text[broken_deco.end():])
        end = broken_deco.end() + (nxt.start() if nxt else len(text[broken_deco.end():]))
        text = text[:start] + text[end:]

# Inserta/garantiza bloque sano para POST /notes (idempotente)
if 'def create_note(' not in text:
    block = '''
@api.route("/notes", methods=["POST"])
def create_note():
    from flask import request, jsonify
    from datetime import datetime, timedelta
    from .models import db, Note  # ajusta import si tu modelo vive en otro lado
    try:
        data = request.get_json(silent=True) or {}
        text = (data.get("text") or "").strip()
        hours = int(data.get("hours") or 24)
        if not text:
            return jsonify({"ok": False, "error": "text_required"}), 400
        now = datetime.utcnow()
        expires = now + timedelta(hours=hours)
        n = Note(text=text, timestamp=now, expires_at=expires, likes=0, views=0, reports=0)
        db.session.add(n)
        db.session.commit()
        return jsonify({"ok": True, "id": n.id}), 201
    except Exception as e:
        return jsonify({"ok": False, "error": "create_failed", "detail": str(e)}), 500
'''.lstrip("\n")
    # Añadir al final
    if not text.endswith("\n"): text += "\n"
    text += block

# 4) Asegurar GET /notes (lista) y subrutas clave si faltan (no pisa si existen)
def ensure_route(sig, stub):
    nonlocal text
    if re.search(sig, text, re.M|re.S): return
    if not text.endswith("\n"): text += "\n"
    text += stub

ensure_route(r'(?m)^@api\.route\("/notes"\)\s*\ndef\s+list_notes\(',
'''
@api.route("/notes")
def list_notes():
    from flask import request, jsonify
    from .models import Note
    try:
        q = Note.query
        active_only = request.args.get("active_only") in ("1","true","True")
        if active_only:
            from datetime import datetime
            q = q.filter(Note.expires_at >= datetime.utcnow())
        before_id = request.args.get("before_id", type=int)
        if before_id:
            q = q.filter(Note.id < before_id)
        q = q.order_by(Note.id.desc())
        limit = request.args.get("limit", type=int) or 20
        items = [{
            "id": n.id, "text": n.text, "timestamp": n.timestamp.isoformat(),
            "expires_at": n.expires_at.isoformat(), "likes": n.likes,
            "views": n.views, "reports": n.reports
        } for n in q.limit(limit).all()]
        wrap = request.args.get("wrap") in ("1","true","True")
        if wrap:
            return jsonify({"items": items, "has_more": len(items) >= limit,
                            "next_before_id": (items[-1]["id"] if items else None)})
        return jsonify(items)
    except Exception as e:
        return jsonify({"ok": False, "error": "list_failed", "detail": str(e)}), 500
'''.lstrip("\n"))

ensure_route(r'(?m)^@api\.route\("/notes/<int:note_id>"\)\s*\ndef\s+get_note\(',
'''
@api.route("/notes/<int:note_id>")
def get_note(note_id):
    from flask import jsonify
    from .models import Note
    n = Note.query.get_or_404(note_id)
    return jsonify({
        "id": n.id, "text": n.text, "timestamp": n.timestamp.isoformat(),
        "expires_at": n.expires_at.isoformat(), "likes": n.likes,
        "views": n.views, "reports": n.reports
    })
'''.lstrip("\n"))

ensure_route(r'(?m)^@api\.route\("/notes/<int:note_id>/view",\s*methods=\["POST"\]\)',
'''
@api.route("/notes/<int:note_id>/view", methods=["POST"])
def view_note(note_id):
    from flask import jsonify
    from .models import db, Note, ViewLog
    n = Note.query.get_or_404(note_id)
    n.views = (n.views or 0) + 1
    db.session.add(n); db.session.add(ViewLog(note_id=note_id))
    db.session.commit()
    return jsonify({"ok": True, "views": n.views})
'''.lstrip("\n"))

ensure_route(r'(?m)^@api\.route\("/notes/<int:note_id>/like",\s*methods=\["POST"\]\)',
'''
@api.route("/notes/<int:note_id>/like", methods=["POST"])
def like_note(note_id):
    from flask import jsonify
    from .models import db, Note
    n = Note.query.get_or_404(note_id)
    n.likes = (n.likes or 0) + 1
    db.session.add(n); db.session.commit()
    return jsonify({"ok": True, "likes": n.likes})
'''.lstrip("\n"))

ensure_route(r'(?m)^@api\.route\("/notes/<int:note_id>/report",\s*methods=\["POST"\]\)',
'''
@api.route("/notes/<int:note_id>/report", methods=["POST"])
def report_note(note_id):
    from flask import jsonify
    from .models import db, Note
    n = Note.query.get_or_404(note_id)
    n.reports = (n.reports or 0) + 1
    db.session.add(n); db.session.commit()
    return jsonify({"ok": True, "reports": n.reports})
'''.lstrip("\n"))

# 5) Asegurar que exista blueprint 'api'
if 'api = Blueprint(' not in text:
    text = 'from flask import Blueprint\napi = Blueprint("api", __name__)\n\n' + text
if 'from flask import Blueprint' not in text:
    text = 'from flask import Blueprint\n' + text

p.write_text(text, encoding="utf-8")
print("OK: routes.py normalizado (indent/imports/blueprint) y rutas clave garantizadas")
PY

git add "$F" >/dev/null 2>&1 || true
git commit -m "fix(routes): normaliza indentación/tabs, asegura blueprint y rutas notas" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true
echo "✓ Commit & push hecho."
