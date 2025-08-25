import re, sys, pathlib

p = pathlib.Path("backend/routes.py")
if not p.exists():
    print("No existe backend/routes.py", file=sys.stderr); sys.exit(1)

src = p.read_text(encoding="utf-8")

# Asegurar import sqlalchemy as sa
if "import sqlalchemy as sa" not in src:
    src = "import sqlalchemy as sa\n" + src

# Localizar def list_notes (independiente del decorador)
m = re.search(r'\n\s*def\s+list_notes\s*\(\s*\)\s*:\s*\n', src)
if not m:
    print("No pude localizar def list_notes()", file=sys.stderr); sys.exit(2)

start = m.end()
# Buscar fin del cuerpo por dedent: primera línea que NO esté indentada (o EOF)
rest = src[start:]
end_rel = None
for i, line in enumerate(rest.splitlines(True)):
    if line.strip() == "":  # líneas en blanco no terminan el bloque
        continue
    # fin de bloque si no empieza con espacios (dedent) o comienza un decorador/def
    if not line.startswith((" ", "\t")) or line.lstrip().startswith(("@api.", "def ")):
        end_rel = sum(len(l) for l in rest.splitlines(True)[:i])
        break
end = start + (end_rel if end_rel is not None else len(rest))

body = r'''
    from flask import request, jsonify
    from backend.models import Note

    # active_only: por defecto true
    raw_active = (request.args.get("active_only", "1") or "").lower()
    active_only = raw_active in ("1","true","on","yes","y")

    # before_id como cursor estricto (id < before_id)
    raw_before = (request.args.get("before_id")
                  or request.args.get("before")
                  or request.args.get("max_id")
                  or request.args.get("cursor"))
    try:
        before_id = int(raw_before) if raw_before is not None else None
    except Exception:
        before_id = None

    # limit acotado
    try:
        limit = int(request.args.get("limit", 20))
    except Exception:
        limit = 20
    limit = max(1, min(100, limit))

    q = Note.query
    if active_only:
        q = q.filter(Note.expires_at > sa.func.now())
    if before_id:
        q = q.filter(Note.id < before_id)
    q = q.order_by(Note.id.desc()).limit(limit)

    rows = q.all()
    items = [n.as_dict() for n in rows]

    # wrap opcional
    raw_wrap = (request.args.get("wrap", "0") or "").lower()
    if raw_wrap in ("1","true","on","yes","y"):
        next_before_id = items[-1]["id"] if len(items) == limit else None
        return jsonify({
            "items": items,
            "has_more": next_before_id is not None,
            "next_before_id": next_before_id,
        })
    return jsonify(items)
'''.lstrip("\n")

new_src = src[:start] + body + src[end:]
p.write_text(new_src, encoding="utf-8")
print("✅ list_notes() actualizado (before_id, active_only, limit, wrap, order DESC)")
