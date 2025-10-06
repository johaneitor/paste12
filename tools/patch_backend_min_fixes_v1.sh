#!/usr/bin/env bash
set -euo pipefail
PY="wsgiapp/__init__.py"
[[ -f "$PY" ]] || { echo "ERROR: falta $PY"; exit 1; }

python - <<'PY'
import io, re, py_compile
p="wsgiapp/__init__.py"
s=io.open(p,"r",encoding="utf-8").read()

def ensure_imports(code):
    hdr=[]
    if "from flask import" not in code:
        hdr.append("from flask import request, jsonify, make_response")
    else:
        if "jsonify" not in code:
            code=re.sub(r'from flask import ([^\n]+)', lambda m: "from flask import "+(m.group(1)+", jsonify"), code, count=1)
        if "make_response" not in code:
            code=re.sub(r'from flask import ([^\n]+)', lambda m: "from flask import "+(m.group(1)+", make_response"), code, count=1)
    if "from flask_limiter" not in code:
        hdr.append("from flask_limiter import Limiter\nfrom flask_limiter.util import get_remote_address")
    if hdr: code="\n".join(hdr)+"\n"+code
    return code

def ensure_constants(code):
    # TTL 72h, CAP 200
    if re.search(r'^\s*TTL_HOURS\s*=\s*\d+', code, re.M):
        code=re.sub(r'^\s*TTL_HOURS\s*=\s*\d+', "TTL_HOURS = 72", code, flags=re.M)
    else:
        code="TTL_HOURS = 72\n"+code
    if re.search(r'^\s*CAP_LIMIT\s*=\s*\d+', code, re.M):
        code=re.sub(r'^\s*CAP_LIMIT\s*=\s*\d+', "CAP_LIMIT = 200", code, flags=re.M)
    else:
        code="CAP_LIMIT = 200\n"+code
    return code

def ensure_limiter(code):
    # después de app = Flask(…) agregar limiter si no existe
    if "Limiter(" in code:
        pass
    else:
        code=re.sub(r'(\bapp\s*=\s*Flask\([^)]*\)\s*)',
                    r'\1\nlimiter = Limiter(get_remote_address, app=app, default_limits=["200 per hour"])\n',
                    code, count=1)
    # Arreglar línea pegada con "application = app"
    code=re.sub(r'\)\s*application\s*=\s*app', ')\napplication = app', code)
    return code

def ensure_housekeeping(code):
    if "_p12_housekeeping_limits" in code: return code
    block = (
        "def _p12_housekeeping_limits():\n"
        "    try:\n"
        "        from datetime import datetime, timedelta\n"
        "        from wsgiapp import db\n"
        "        from wsgiapp.models import Note\n"
        "        cutoff = datetime.utcnow() - timedelta(hours=TTL_HOURS)\n"
        "        try:\n"
        "            db.session.query(Note).filter(Note.created_at < cutoff).delete(synchronize_session=False)\n"
        "            db.session.commit()\n"
        "        except Exception:\n"
        "            db.session.rollback()\n"
        "        total = db.session.query(Note).count()\n"
        "        if total > CAP_LIMIT:\n"
        "            rows = db.session.query(Note).order_by((Note.likes + Note.views + Note.reports).asc(), Note.created_at.asc()).all()\n"
        "            drop = total - CAP_LIMIT\n"
        "            for n in rows[:drop]:\n"
        "                db.session.delete(n)\n"
        "            db.session.commit()\n"
        "    except Exception:\n"
        "        pass\n"
    )
    return code + "\n" + block

def ensure_bump(code):
    if "_p12_bump_counter" in code: return code
    block = (
        "def _p12_bump_counter(kind, note_id):\n"
        "    try:\n"
        "        from wsgiapp import db\n"
        "        from wsgiapp.models import Note\n"
        "    except Exception:\n"
        "        return None\n"
        "    col = {'like':'likes','view':'views','report':'reports'}.get(kind)\n"
        "    if not col: return None\n"
        "    try:\n"
        "        from sqlalchemy import update\n"
        "        stmt = update(Note).where(Note.id==note_id).values(**{col: getattr(Note, col)+1}).returning(Note.id, Note.likes, Note.views, Note.reports)\n"
        "        res = db.session.execute(stmt).first()\n"
        "        if not res: return None\n"
        "        db.session.commit()\n"
        "        return {'id': res[0], 'likes': res[1], 'views': res[2], 'reports': res[3]}\n"
        "    except Exception:\n"
        "        try:\n"
        "            item = Note.query.get(note_id)\n"
        "            if not item: return None\n"
        "            setattr(item, col, (getattr(item,col) or 0) + 1)\n"
        "            db.session.commit()\n"
        "            return {'id': item.id, 'likes': item.likes, 'views': item.views, 'reports': item.reports}\n"
        "        except Exception:\n"
        "            return None\n"
    )
    return code + "\n" + block

def ensure_notes_route_methods_and_post(code):
    # decorator: añadir methods si no están
    code=re.sub(r'@app\.route\(["\']/api/notes["\']\)',
                '@app.route("/api/notes", methods=["GET","POST","OPTIONS"])',
                code)
    code=re.sub(r'(@app\.route\(["\']/api/notes["\']\s*,\s*methods=\[)([^\]]+)\]\)',
                lambda m: m.group(1)+('"GET","POST","OPTIONS"' if not all(k in m.group(2) for k in ['"GET"','"POST"','"OPTIONS"']) else m.group(2)) + "] )",
                code)

    m = re.search(r'@app\.route\(["\']/api/notes["\'][^\)]*\)\s*\ndef\s+([A-Za-z0-9_]+)\s*\(\s*\)\s*:\s*\n', code)
    if not m: return code
    idx = m.end(0)
    indent = re.match(r'[ \t]*', code[idx:]).group(0)
    sentinel = "p12: POST create"
    if sentinel in code[idx: idx+400]:  # ya inyectado
        return code
    insert = (
        f"{indent}# {sentinel}\n"
        f"{indent}if request.method == 'OPTIONS':\n"
        f"{indent}    return make_response('', 204)\n"
        f"{indent}if request.method == 'POST':\n"
        f"{indent}    data = (request.get_json(silent=True) or request.form or {{}})\n"
        f"{indent}    text = (data.get('text') or '').strip()\n"
        f"{indent}    if not text:\n"
        f"{indent}        return jsonify(error='text_required'), 400\n"
        f"{indent}    try:\n"
        f"{indent}        from wsgiapp import db\n"
        f"{indent}        from wsgiapp.models import Note\n"
        f"{indent}        nn = Note(text=text)\n"
        f"{indent}        db.session.add(nn); db.session.commit()\n"
        f"{indent}        _p12_housekeeping_limits()\n"
        f"{indent}        return jsonify(id=nn.id), 201\n"
        f"{indent}    except Exception:\n"
        f"{indent}        return jsonify(error='create_failed'), 500\n"
        f"{indent}# clamp ?limit=\n"
        f"{indent}try:\n"
        f"{indent}    lim = int(request.args.get('limit','10'))\n"
        f"{indent}except Exception:\n"
        f"{indent}    lim = 10\n"
        f"{indent}if lim < 1: lim = 1\n"
        f"{indent}if lim > 25: lim = 25\n"
    )
    return code[:idx] + insert + code[idx:]

def harden_rest(code, name):
    dec = r'@app\.route\(["\']/api/'+name+r'["\'][^\)]*\)\s*\ndef\s+[A-Za-z0-9_]+\s*\(\s*\)\s*:\s*\n'
    m = re.search(dec, code)
    if not m: return code
    pos = m.end(0)
    indent = re.match(r'[ \t]*', code[pos:]).group(0)
    sent = f"p12: REST {name} guard"
    if sent in code[pos:pos+400]: return code
    blk = (
        f"{indent}# {sent}\n"
        f"{indent}id_str = (request.args.get('id') if request.method=='GET' else ((request.get_json(silent=True) or {{}}).get('id') or request.form.get('id')))\n"
        f"{indent}try:\n"
        f"{indent}    nid = int(id_str)\n"
        f"{indent}except Exception:\n"
        f"{indent}    return jsonify(error='bad_id'), 404\n"
        f"{indent}row = _p12_bump_counter('{name}', nid)\n"
        f"{indent}if not row:\n"
        f"{indent}    return jsonify(error='not_found'), 404\n"
    )
    if name=="report":
        blk += (
            f"{indent}# p12: borrar con 3+ reportes\n"
            f"{indent}if int(row.get('reports',0)) >= 3:\n"
            f"{indent}    try:\n"
            f"{indent}        from wsgiapp import db\n"
            f"{indent}        from wsgiapp.models import Note\n"
            f"{indent}        itm = Note.query.get(nid)\n"
            f"{indent}        if itm:\n"
            f"{indent}            db.session.delete(itm); db.session.commit()\n"
            f"{indent}    except Exception:\n"
            f"{indent}        pass\n"
        )
    blk += f"{indent}return jsonify(row), 200\n"
    return code[:pos] + blk + code[pos:]

s = ensure_imports(s)
s = ensure_constants(s)
s = ensure_limiter(s)
s = ensure_housekeeping(s)
s = ensure_bump(s)
s = ensure_notes_route_methods_and_post(s)
for ep in ("like","view","report"):
    s = harden_rest(s, ep)

# Guardas
io.open(p,"w",encoding="utf-8").write(s)
py_compile.compile(p, doraise=True)
print("PATCH_OK", p)
PY

python -m py_compile wsgiapp/__init__.py && echo "OK: wsgiapp/__init__.py compilado"
