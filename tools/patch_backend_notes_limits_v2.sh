#!/usr/bin/env bash
set -euo pipefail
PY="wsgiapp/__init__.py"
[[ -f "$PY" ]] || { echo "ERROR: falta $PY"; exit 1; }

python - <<'PY'
import io, re, py_compile

p="wsgiapp/__init__.py"
s=io.open(p,"r",encoding="utf-8").read()

def ensure(import_line, mod):
    if import_line not in mod:
        return import_line + "\n" + mod
    return mod

# 0) Imports útiles
s = ensure("from flask import request, jsonify, make_response", s)
if "from flask_limiter" not in s:
    s = "from flask_limiter import Limiter\nfrom flask_limiter.util import get_remote_address\n" + s

# 1) Definir/actualizar constantes de límites
if "TTL_HOURS" not in s: s = "TTL_HOURS = 72\n" + s
s = re.sub(r'(?m)^\s*TTL_HOURS\s*=\s*\d+\s*$', "TTL_HOURS = 72", s)

# CAP: duplicado (p.ej. 200)
if "CAP_LIMIT" not in s: s = "CAP_LIMIT = 200\n" + s
s = re.sub(r'(?m)^\s*CAP_LIMIT\s*=\s*\d+\s*$', "CAP_LIMIT = 200", s)

# 2) Instanciar Limiter si no existe
if "Limiter(" not in s or " limiter = " not in s:
    # Busca 'app = Flask('
    if re.search(r'\bapp\s*=\s*Flask\(', s):
        s = re.sub(r'(\bapp\s*=\s*Flask\([^)]*\)\s*)',
                   r'\1\nlimiter = Limiter(get_remote_address, app=app, default_limits=["200 per hour"])',
                   s, count=1)

# 3) Helper único para like/view/report con UPDATE…RETURNING ó guard SELECT
if "_p12_bump_counter" not in s:
    s += r"""

# --- paste12 helpers (únicos) ---
def _p12_bump_counter(kind, note_id):
    """
    Actualiza counters de la nota y devuelve dict con id y contadores.
    Si no existe => 404 (mapped por caller).
    Implementación genérica: intenta SQLAlchemy; si no, fallback select+update.
    """
    try:
        from wsgiapp import db
        from wsgiapp.models import Note  # si existe
    except Exception:
        db = None
        Note = None

    # Intento SQLAlchemy
    if db and Note:
        from sqlalchemy import update, text
        col = {"like":"likes","view":"views","report":"reports"}.get(kind)
        if not col: return None
        try:
            stmt = update(Note).where(Note.id==note_id)\
                    .values(**{col: getattr(Note, col) + 1})\
                    .returning(Note.id, Note.likes, Note.views, Note.reports)
            res = db.session.execute(stmt).first()
            if not res: return None
            db.session.commit()
            data = {"id": res[0], "likes": res[1], "views": res[2], "reports": res[3]}
        except Exception:
            # Fallback: SELECT + UPDATE
            item = Note.query.get(note_id)
            if not item: 
                return None
            setattr(item, col, (getattr(item,col) or 0) + 1)
            db.session.commit()
            data = {"id": item.id, "likes": item.likes, "views": item.views, "reports": item.reports}
        return data
    return None
"""

# 4) Arreglar /api/notes: permitir POST/OPTIONS, clamp limit<=25, anti-abuso
# Decorador: agregar POST/OPTIONS si falta
s = re.sub(
    r'(@app\.route\(["\']/api/notes["\']\s*,\s*methods=\[)([^\]]+)\]\)',
    lambda m: m.group(1) + ('"GET","POST","OPTIONS"' if "POST" not in m.group(2) else m.group(2)) + '])',
    s
)

# Si no tenía methods=..., añadimos uno completo
if not re.search(r'@app\.route\(["\']/api/notes["\'].*methods=', s):
    s = re.sub(r'@app\.route\(["\']/api/notes["\']\)', 
               '@app.route("/api/notes", methods=["GET","POST","OPTIONS"])',
               s)

# Clampear limit y manejar POST/OPTIONS dentro de la función handler
def patch_notes_func(mod):
    pat = r'def\s+([a-zA-Z_0-9]+)\s*\(\s*\)\s*:\s*\n'
    m = re.search(r'@app\.route\(["\']/api/notes["\'][^\)]*\)\s*\n' + pat, mod)
    if not m: return mod
    start = m.start(0)
    func_name = m.group(1)
    # Busca el cuerpo de la función (indenta al mismo nivel)
    body_start = m.end(0)
    indent = re.match(r'[ \t]*', mod[body_start:]).group(0)
    # Inyecta cabecera de control de métodos y clamp
    inject = f'''{indent}# p12: OPTIONS
{indent}if request.method == "OPTIONS":
{indent}    return make_response("", 204)
{indent}# p12: POST (crear nota)
{indent}if request.method == "POST":
{indent}    data = (request.get_json(silent=True) or request.form or {{}})
{indent}    text = (data.get("text") or "").strip()
{indent}    if not text:
{indent}        return jsonify(error="text_required"), 400
{indent}    try:
{indent}        from wsgiapp import db
{indent}        from wsgiapp.models import Note
{indent}        nn = Note(text=text)
{indent}        db.session.add(nn)
{indent}        db.session.commit()
{indent}        # p12: house-keeping límites
{indent}        _p12_housekeeping_limits()
{indent}        return jsonify(id=nn.id), 201
{indent}    except Exception:
{indent}        return jsonify(error="create_failed"), 500
{indent}# p12: GET con clamp limit<=25
{indent}try:
{indent}    lim = int(request.args.get("limit","10"))
{indent}except Exception:
{indent}    lim = 10
{indent}if lim < 1: lim = 1
{indent}if lim > 25: lim = 25
'''
    # Inserta después de la firma si no existe ya
    if "p12: OPTIONS" not in mod[body_start:body_start+400]:
        mod = mod[:body_start] + inject + mod[body_start:]
    return mod

s = patch_notes_func(s)

# 5) Endpoints like/view/report → 404 limpio + report>=3 borra
def harden_endpoint(mod, name, method="GET"):
    # Busca función correspondiente
    dec = r'@app\.route\(["\']/api/'+name+r'["\'].*\)\s*\n'
    m = re.search(dec + r'def\s+([a-zA-Z_0-9]+)\s*\(\s*\)\s*:\s*\n', mod)
    if not m: return mod
    fn = m.group(1)
    pos = m.end(0)
    indent = re.match(r'[ \t]*', mod[pos:]).group(0)
    guard = f'''{indent}# p12: leer id (GET o JSON/FORM)
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
        guard += f'''{indent}# p12: report threshold => 3
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
    guard += f'''{indent}return jsonify(row), 200
'''
    # inserta sólo si no hay ya "p12: leer id"
    if "p12: leer id" not in mod[pos:pos+400]:
        mod = mod[:pos] + guard + mod[pos:]
    # Añadir limiters suaves
    if "@limiter.limit" not in mod[m.start():m.end()+200]:
        mod = mod[:m.start()] + '@limiter.limit("20 per minute")\n' + mod[m.start():]
    return mod

s = harden_endpoint(s, "like")
s = harden_endpoint(s, "view")
s = harden_endpoint(s, "report")

# 6) House-keeping (TTL/CAP)
if "_p12_housekeeping_limits" not in s:
    s += r"""

def _p12_housekeeping_limits():
    try:
        from datetime import datetime, timedelta
        from wsgiapp import db
        from wsgiapp.models import Note
        # TTL
        cutoff = datetime.utcnow() - timedelta(hours=TTL_HOURS)
        # borra viejas por TTL
        try:
            db.session.query(Note).filter(Note.created_at < cutoff).delete(synchronize_session=False)
            db.session.commit()
        except Exception:
            db.session.rollback()
        # CAP: mantener las más relevantes y recientes
        total = db.session.query(Note).count()
        if total > CAP_LIMIT:
            # heurística: ordenar por (likes + views + reports, created_at)
            rows = db.session.query(Note).order_by((Note.likes + Note.views + Note.reports).asc(), Note.created_at.asc()).all()
            drop = total - CAP_LIMIT
            for n in rows[:drop]:
                db.session.delete(n)
            db.session.commit()
    except Exception:
        pass
"""

# 7) Compilar
io.open(p,"w",encoding="utf-8").write(s)
py_compile.compile(p, doraise=True)
print("PATCH_OK", p)
PY

python -m py_compile wsgiapp/__init__.py && echo "OK: wsgiapp/__init__.py compilado"
