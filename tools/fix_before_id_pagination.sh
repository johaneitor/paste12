#!/usr/bin/env bash
set -euo pipefail

F="backend/routes.py"
[[ -f "$F" ]] || { echo "No existe $F"; exit 1; }

python - "$F" <<'PY'
import re, sys, io, os
p = sys.argv[1]
src = open(p, "r", encoding="utf-8").read()

# Asegurarnos de tener imports necesarios
if "import sqlalchemy as sa" not in src:
    src = "import sqlalchemy as sa\n" + src

# Regex que localiza toda la función list_notes (la decorada con /api/notes GET)
pat = re.compile(
    r'(@api\.route\(\s*"/notes"\s*\)\s*def\s+list_notes\s*\(\s*\)\s*:\s*)'  # cabecera
    r'([\s\S]*?)'                                                            # cuerpo
    r'(?=\n@api\.route|\n#\s*end\s+list_notes|\Z)',                          # hasta el siguiente route o EOF
    re.M
)

if not pat.search(src):
    # Variante: tal vez está con methods=["GET"]
    pat = re.compile(
        r'(@api\.route\(\s*"/notes"\s*,\s*methods\s*=\s*\[\s*"GET"\s*\]\s*\)\s*def\s+list_notes\s*\(\s*\)\s*:\s*)'
        r'([\s\S]*?)'
        r'(?=\n@api\.route|\n#\s*end\s+list_notes|\Z)',
        re.M
    )

m = pat.search(src)
if not m:
    print("No pude localizar def list_notes() decorada con /api/notes", file=sys.stderr)
    sys.exit(2)

head = m.group(1)

body = r'''
    from flask import request, jsonify
    from backend.models import Note
    import sqlalchemy as sa

    # --- filtros de consulta ---
    # active_only: por defecto true si viene "1"/"true"/"on"
    raw_active = (request.args.get("active_only", "1") or "").lower()
    active_only = raw_active in ("1","true","on","yes","y")

    # before_id: cursor estricto (id < before_id)
    raw_before = request.args.get("before_id") or request.args.get("before") or request.args.get("max_id") or request.args.get("cursor")
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

    # build query
    q = Note.query
    if active_only:
        q = q.filter(Note.expires_at > sa.func.now())
    if before_id:
        q = q.filter(Note.id < before_id)
    q = q.order_by(Note.id.desc()).limit(limit)

    rows = q.all()
    items = [n.as_dict() for n in rows]

    # wrap opcional: {items, has_more, next_before_id}
    raw_wrap = (request.args.get("wrap", "0") or "").lower()
    if raw_wrap in ("1","true","on","yes","y"):
        next_before_id = items[-1]["id"] if len(items) == limit else None
        return jsonify({
            "items": items,
            "has_more": next_before_id is not None,
            "next_before_id": next_before_id,
        })
    else:
        return jsonify(items)
'''.rstrip("\n")

new = pat.sub(head + body, src, count=1)

open(p, "w", encoding="utf-8").write(new)
print("✅ list_notes() actualizado con paginación basada en before_id, active_only, limit y wrap")
PY
