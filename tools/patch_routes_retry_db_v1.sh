#!/usr/bin/env bash
set -euo pipefail
TARGET="backend/routes.py"
[[ -f "$TARGET" ]] || { echo "ERROR: falta $TARGET"; exit 1; }
TS="$(date -u +%Y%m%d-%H%M%SZ)"
BAK="$TARGET.$TS.bak"
cp -f "$TARGET" "$BAK"
echo "[routes-retry] Backup: $BAK"

python - <<'PY'
import io, re
p="backend/routes.py"
s=io.open(p,"r",encoding="utf-8").read()

helpers = r'''
# == Paste12 retry helpers ==
from sqlalchemy.exc import OperationalError, DBAPIError
def _retry_db(fn, attempts=2):
    from flask import current_app as _app
    from backend import db
    last = None
    for i in range(attempts):
        try:
            return fn()
        except (OperationalError, DBAPIError) as e:
            last = e
            try:
                db.session.rollback()
                db.engine.dispose()
            except Exception:
                pass
    # última chance: respuesta suave
    return None, last
# == /retry helpers ==
'''

if "== Paste12 retry helpers ==" not in s:
    # meter helpers cerca del top (después de imports)
    s = re.sub(r'(\nfrom\s+flask[^\n]*\n)',
               r'\1'+helpers,
               s, count=1)

def patch_list_notes(txt):
    # intentamos localizar la función de listado por /api/notes
    m = re.search(r'@app\.route\(["\']/api/notes[^)]*\)\s*def\s+(\w+)\s*\(\):', txt)
    if not m:
        return txt
    fn = m.group(1)
    # reemplazar cuerpo entre def ...: y el próximo decorador/EOF
    body_re = re.compile(rf'(def\s+{fn}\s*\(\):\s*)([\s\S]*?)(?=\n@|\Z)', re.M)
    def repl(mm):
        header = mm.group(1)
        new_body = '''
    from flask import request, jsonify, Response
    from backend import db
    from backend.models import Note  # si aplica
    limit = max(1, min(50, int(request.args.get("limit", 10))))
    before_id = request.args.get("before_id")
    def _do():
        q = Note.query
        if before_id:
            try:
                q = q.filter(Note.id < int(before_id))
            except Exception:
                pass
        items = q.order_by(Note.timestamp.desc()).limit(limit).all()
        return items, None
    res, err = _retry_db(_do)
    if res is None:
        # degradación suave para no romper el FE
        return jsonify({"ok": False, "error":"db_unavailable"}), 503
    items = res
    # serializar
    out = []
    for n in items:
        out.append({
            "id": n.id, "text": n.text, "timestamp": n.timestamp.isoformat(),
            "expires_at": getattr(n, "expires_at", None).isoformat() if getattr(n,"expires_at",None) else None,
            "likes": getattr(n,"likes",0), "views": getattr(n,"views",0), "reports": getattr(n,"reports",0),
            "author_fp": getattr(n,"author_fp", None),
        })
    # Link rel=next
    if items:
        next_cursor = items[-1].id
        hdr = f'<{request.url_root.rstrip("/")}/api/notes?limit={limit}&before_id={next_cursor}>; rel="next"'
        resp = jsonify(out)
        resp.headers["Link"] = hdr
        return resp
    return jsonify(out)
'''
        return header + new_body
    txt = body_re.sub(repl, txt)
    return txt

def patch_mutation(name, route):
    # like/view/report → envolver en retry
    pat = re.compile(rf'@app\.route\(["\']{re.escape(route)}["\'][^\)]*\)\s*def\s+(\w+)\s*\(([^)]*)\):([\s\S]*?)(?=\n@|\Z)', re.M)
    def repl(mm):
        fname, args, body = mm.group(1), mm.group(2), mm.group(3)
        safe = f'''
def {fname}({args}):
    from flask import jsonify
    from backend import db
    def _do():
{ "        ".join(("        "+ln if ln.strip() else "") for ln in body.splitlines(True)) }
        return {"ok": True}, None
    res, err = _retry_db(_do)
    if res is None:
        return jsonify({{"ok": False, "error":"db_unavailable"}}), 503
    return jsonify({{"ok": True}})
'''
        return '@app.route("'+route+'", methods=["POST"])\n' + safe
    return pat.sub(repl, s)

s = patch_list_notes(s)
s = patch_mutation("like_note", "/api/notes/<int:note_id>/like")
s = patch_mutation("view_note", "/api/notes/<int:note_id>/view")
s = patch_mutation("report_note", "/api/notes/<int:note_id>/report")

io.open(p,"w",encoding="utf-8").write(s)
PY

python -m py_compile backend/routes.py && echo "[routes-retry] py_compile OK" || { echo "[routes-retry] py_compile FAIL"; exit 2; }
echo "Listo. Si no quieres el retry, restaura el .bak."
