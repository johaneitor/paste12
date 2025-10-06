#!/usr/bin/env bash
set -euo pipefail
PY="wsgiapp/__init__.py"
[[ -f "$PY" ]] || { echo "ERROR: falta $PY"; exit 1; }

python - <<'PY'
import io, re, py_compile
p="wsgiapp/__init__.py"
s=io.open(p,"r",encoding="utf-8").read()

def ensure(line, mod):
    return line+"\n"+mod if line not in mod else mod

# Imports necesarios
s = ensure("from flask import request, jsonify, make_response", s)
if "from flask_limiter" not in s:
    s = "from flask_limiter import Limiter\nfrom flask_limiter.util import get_remote_address\n" + s

# Constantes de límites
if "TTL_HOURS" not in s: s = "TTL_HOURS = 72\n" + s
s = re.sub(r'(?m)^\s*TTL_HOURS\s*=\s*\d+\s*$', "TTL_HOURS = 72", s)
if "CAP_LIMIT" not in s: s = "CAP_LIMIT = 200\n" + s
s = re.sub(r'(?m)^\s*CAP_LIMIT\s*=\s*\d+\s*$', "CAP_LIMIT = 200", s)

# Instanciar Limiter
if re.search(r'\blimiter\s*=\s*Limiter\(', s) is None and re.search(r'\bapp\s*=\s*Flask\(', s):
    s = re.sub(r'(\bapp\s*=\s*Flask\([^)]*\)\s*)',
               r'\1\nlimiter = Limiter(get_remote_address, app=app, default_limits=["200 per hour"])',
               s, count=1)

# Helper centralizado
if "_p12_bump_counter" not in s:
    s += r'''
def _p12_bump_counter(kind, note_id):
    """Actualiza like/view/report y devuelve dict con id/counters; None si no existe."""
    try:
        from wsgiapp import db
        from wsgiapp.models import Note
    except Exception:
        return None
    col = {"like":"likes","view":"views","report":"reports"}.get(kind)
    if not col: return None
    try:
        from sqlalchemy import update
        stmt = update(Note).where(Note.id==note_id)\
                .values(**{col: getattr(Note, col) + 1})\
                .returning(Note.id, Note.likes, Note.views, Note.reports)
        res = db.session.execute(stmt).first()
        if not res: return None
        db.session.commit()
        return {"id": res[0], "likes": res[1], "views": res[2], "reports": res[3]}
    except Exception:
        # Fallback ORM
        try:
            item = Note.query.get(note_id)
            if not item: return None
            setattr(item, col, (getattr(item,col) or 0) + 1)
            db.session.commit()
            return {"id": item.id, "likes": item.likes, "views": item.views, "reports": item.reports}
        except Exception:
            return None
'''

# /api/notes debe aceptar GET/POST/OPTIONS
if not re.search(r'@app\.route\(["\']/api/notes["\'].*methods=', s):
    s = re.sub(r'@app\.route\(["\']/api/notes["\']\)', 
               '@app.route("/api/notes", methods=["GET","POST","OPTIONS"])',
               s)

s = re.sub(
    r'(@app\.route\(["\']/api/notes["\']\s*,\s*methods=\[)([^\]]+)\]\)',
    lambda m: m.group(1) + 
        (m.group(2) if all(x in m.group(2) for x in ('"GET"','"POST"','"OPTIONS"')) else '"GET","POST","OPTIONS"') + '])',
    s
)

# Inyectar manejo de OPTIONS/POST + clamp limit en la función
m = re.search(r'@app\.route\(["\']/api/notes["\'][^\)]*\)\s*\ndef\s+([A-Za-z0-9_]+)\s*\(\s*\)\s*:\s*\n', s)
if m:
    body_start = m.end(0)
    indent = re.match(r'[ \t]*', s[body_start:]).group(0)
    inject = f'''{indent}# p12: CORS/preflight
{indent}if request.method == "OPTIONS":
{indent}    return make_response("", 204)
{indent}# p12: creación por POST
{indent}if request.method == "POST":
{indent}    data = (request.get_json(silent=True) or request.form or {{}})
{indent}    text = (data.get("text") or "").strip()
{indent}    if not text:
{indent}        return jsonify(error="text_required"), 400
{indent}    try:
{indent}        from wsgiapp import db
{indent}        from wsgiapp.models import Note
{indent}        nn = Note(text=text)
{indent}        db.session.add(nn); db.session.commit()
{indent}        _p12_housekeeping_limits()
{indent}        return jsonify(id=nn.id), 201
{indent}    except Exception:
{indent}        return jsonify(error="create_failed"), 500
{indent}# p12: clamp del GET ?limit=
{indent}try:
{indent}    lim = int(request.args.get("limit","10"))
{indent}except Exception:
{indent}    lim = 10
{indent}if lim < 1: lim = 1
{indent}if lim > 25: lim = 25
'''
    if "p12: CORS/preflight" not in s[body_start:body_start+400]:
        s = s[:body_start] + inject + s[body_start:]

# Endpoints like/view/report con 404 y report>=3 borra
def harden(name):
    dec = r'@app\.route\(["\']/api/'+name+r'["\'][^\)]*\)\s*\ndef\s+[A-Za-z0-9_]+\s*\(\s*\)\s*:\s*\n'
    m = re.search(dec, s)
    if not m: return
    pos = m.end(0)
    indent = re.match(r'[ \t]*', s[pos:]).group(0)
    blk = f'''{indent}# p12: leer id (GET/JSON/FORM)
{indent}id_str = (request.args.get("id") if request.method=="GET" else ((request.get_json(silent=True) or {{}}).get("id") or request.form.get("id")))
{indent}try:
{indent}    nid = int(id_str)
{indent}except Exception:
{indent}    return jsonify(error="bad_id"), 404
{indent}row = _p12_bump_counter("{name}", nid)
{indent}if not row:
{indent}    return jsonify(error="not_found"), 404
'''
    if name=="report":
        blk += f'''{indent}# p12: al llegar a 3 reportes, borrar
{indent}if int(row.get("reports",0)) >= 3:
{indent}    try:
{indent}        from wsgiapp import db
{indent}        from wsgiapp.models import Note
{indent}        itm = Note.query.get(nid)
{indent}        if itm:
{indent}            db.session.delete(itm); db.session.commit()
{indent}    except Exception:
{indent}        pass
'''
    blk += f'''{indent}return jsonify(row), 200
'''
    if "p12: leer id" not in s[pos:pos+400]:
        globals()['s'] = s[:pos] + blk + s[pos:]

for ep in ("like","view","report"):
    harden(ep)

# House-keeping TTL/CAP
if "_p12_housekeeping_limits" not in s:
    s += r'''
def _p12_housekeeping_limits():
    try:
        from datetime import datetime, timedelta
        from wsgiapp import db
        from wsgiapp.models import Note
        cutoff = datetime.utcnow() - timedelta(hours=TTL_HOURS)
        try:
            db.session.query(Note).filter(Note.created_at < cutoff).delete(synchronize_session=False)
            db.session.commit()
        except Exception:
            db.session.rollback()
        total = db.session.query(Note).count()
        if total > CAP_LIMIT:
            rows = db.session.query(Note).order_by((Note.likes + Note.views + Note.reports).asc(), Note.created_at.asc()).all()
            drop = total - CAP_LIMIT
            for n in rows[:drop]:
                db.session.delete(n)
            db.session.commit()
    except Exception:
        pass
'''

io.open(p,"w",encoding="utf-8").write(s)
py_compile.compile(p, doraise=True)
print("PATCH_OK", p)
PY

python -m py_compile wsgiapp/__init__.py && echo "OK: wsgiapp/__init__.py compilado"
