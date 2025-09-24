#!/usr/bin/env bash
set -euo pipefail

FILE="backend/routes.py"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p backend tools
[[ -f "$FILE" ]] && cp -f "$FILE" "backend/routes.$TS.bak" || true

python - <<'PY'
import io, os, re, textwrap
p="backend/routes.py"
base=textwrap.dedent(r'''
from flask import Blueprint, request, jsonify, abort
from .models import Note
from . import db

bp = Blueprint("api", __name__, url_prefix="/api")

@bp.route("/health", methods=["GET","HEAD","OPTIONS"])
def api_health():
    return jsonify(ok=True, api=True)

@bp.route("/notes", methods=["GET","HEAD","OPTIONS","POST"])
def list_or_create_notes():
    if request.method in ("GET","HEAD"):
        # paginado básico + Link
        limit = int(request.args.get("limit", 10))
        before_id = request.args.get("before_id", type=int)
        q = Note.query
        if before_id:
            q = q.filter(Note.id < before_id)
        items = q.order_by(Note.timestamp.desc()).limit(limit).all()
        data = [n.as_json() for n in items]
        # Link rel=next si hay más
        hdrs = {}
        if items:
            last_id = items[-1].id
            hdrs["Link"] = f'</api/notes?limit={limit}&before_id={last_id}>; rel="next"'
        return (jsonify(data), 200, hdrs)
    # POST (JSON o FORM)
    text = (request.json or {}).get("text") if request.is_json else request.form.get("text")
    if not text:
        return jsonify(error="text required"), 400
    n = Note(text=text)
    db.session.add(n); db.session.commit()
    return jsonify(n.as_json()), 201

def _get_note_or_404(note_id:int):
    n = Note.query.get(note_id)
    if not n: abort(404)
    return n

@bp.route("/notes/<int:note_id>/like", methods=["POST","OPTIONS"])
def like_note(note_id):
    n = _get_note_or_404(note_id)
    n.likes = (n.likes or 0) + 1
    db.session.commit()
    return jsonify(ok=True, id=n.id, likes=n.likes), 200

@bp.route("/notes/<int:note_id>/view", methods=["POST","OPTIONS"])
def view_note(note_id):
    n = _get_note_or_404(note_id)
    n.views = (n.views or 0) + 1
    db.session.commit()
    return jsonify(ok=True, id=n.id, views=n.views), 200

@bp.route("/notes/<int:note_id>/report", methods=["POST","OPTIONS"])
def report_note(note_id):
    n = _get_note_or_404(note_id)
    n.reports = (n.reports or 0) + 1
    db.session.commit()
    return jsonify(ok=True, id=n.id, reports=n.reports), 200
''').lstrip()

def ensure_routes(s:str)->str:
    # Asegura blueprint url_prefix="/api"
    if not re.search(r'Blueprint\([^)]*url_prefix\s*=\s*["\']\/api["\']', s):
        s = re.sub(r'Blueprint\((.*?)\)', r'Blueprint(\1, url_prefix="/api")', s, count=1, flags=re.S)
    # Asegura métodos en /notes
    s = re.sub(r'@bp\.route\(["\']/notes["\']\)(\s*def)',
               '@bp.route("/notes", methods=["GET","HEAD","OPTIONS","POST"])\\1', s)
    # like/view/report POST
    for name in ("like","view","report"):
        s = re.sub(
            rf'@bp\.route\(["\']/notes/<int:note_id>/{name}["\']\)(\s*def)',
            rf'@bp.route("/notes/<int:note_id>/{name}", methods=["POST","OPTIONS"])\\1',
            s
        )
    return s

if not os.path.exists(p):
    io.open(p,"w",encoding="utf-8").write(base)
    print(f"[routes] creado {p}")
else:
    s = io.open(p,"r",encoding="utf-8").read()
    orig = s
    # Si no hay endpoints mínimos, injertamos el bloque base completo al final.
    has_notes = re.search(r'@bp\.route\(["\']/notes', s) is not None
    if has_notes:
        s = ensure_routes(s)
    else:
        s = s.rstrip()+"\n\n"+base
    if s != orig:
        io.open(p,"w",encoding="utf-8").write(s)
        print("[routes] métodos/blueprint normalizados")
    else:
        print("[routes] ya estaba OK")
PY

# Asegurar registro del blueprint en backend/__init__.py (create_app)
python - <<'PY'
import io, re, os
p="backend/__init__.py"
if not os.path.exists(p):
    raise SystemExit("ERROR: falta backend/__init__.py")
s=io.open(p,"r",encoding="utf-8").read(); orig=s
# import seguro
if "from .routes import bp as api_bp" not in s:
    s=s.replace("from . import db", "from . import db\nfrom .routes import bp as api_bp")
# registrar en create_app
if re.search(r'app\.register_blueprint\(\s*api_bp\s*\)', s) is None:
    s=re.sub(r'(def\s+create_app\(.*?\):\s*\n\s*app\s*=.*?\n)',
             r'\1    app.register_blueprint(api_bp)\n',
             s, flags=re.S)
if s!=orig:
    io.open(p,"w",encoding="utf-8").write(s)
    print("[init] blueprint /api registrado")
else:
    print("[init] blueprint ya estaba")
PY

python -m py_compile backend/__init__.py backend/routes.py 2>/dev/null && echo "py_compile OK"
echo "Hecho."
