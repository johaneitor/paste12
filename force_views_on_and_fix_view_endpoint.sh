#!/usr/bin/env bash
set -Eeuo pipefail

python - <<'PY'
from pathlib import Path, re
p = Path('backend/routes.py')
s = p.read_text(encoding='utf-8')

# 1) Helper para “views enabled” que siempre vuelve True salvo que EXPRESAMENTE se ponga 0
if '_views_enabled' not in s:
    s = s.replace('def _fp()', '''def _views_enabled():
    import os
    # por defecto on (1). Sólo se apaga con ENABLE_VIEWS="0"
    return (os.getenv("ENABLE_VIEWS","1") != "0")

def _fp()''')

# 2) Reemplazar el endpoint /view completo por una versión robusta
pat = r'@bp\.post\("/notes/<int:note_id>/view"\)[\s\S]*?return jsonify\([^\)]*\)\)\n'
repl = r'''@bp.post("/notes/<int:note_id>/view")
def view_note(note_id: int):
    # Vista única por fingerprint y día (UTC). Postgres: ON CONFLICT DO NOTHING.
    from flask import jsonify, current_app
    import os
    from sqlalchemy import text
    n = Note.query.get_or_404(note_id)

    # Si alguien dejó un kill-switch, lo ignoramos salvo que esté explícitamente en "0"
    if not _views_enabled():
        return jsonify({"counted": False, "views": int(n.views or 0), "disabled": True})

    fp = _fp() or "anon"
    today = _now().date()
    counted = False
    try:
        dialect = db.session.bind.dialect.name

        if dialect == "postgresql":
            # Intento de inserción idempotente por (note_id, fp, view_date)
            row = db.session.execute(text("""
                INSERT INTO view_log (note_id, fingerprint, view_date, created_at)
                VALUES (:nid, :fp, :vd, (NOW() AT TIME ZONE 'UTC'))
                ON CONFLICT (note_id, fingerprint, view_date) DO NOTHING
                RETURNING id
            """), {"nid": note_id, "fp": fp, "vd": today}).first()

            if row:
                db.session.execute(text("UPDATE note SET views = COALESCE(views,0)+1 WHERE id=:nid"),
                                   {"nid": note_id})
                counted = True

            # Leer valor actual para responder
            v = db.session.execute(text("SELECT COALESCE(views,0) FROM note WHERE id=:nid"),
                                   {"nid": note_id}).scalar() or 0
            db.session.commit()
            return jsonify({"counted": counted, "views": int(v)})

        else:
            # SQLite/u otros: ORM + UNIQUE (note_id, fp, view_date) maneja duplicados
            try:
                db.session.add(ViewLog(note_id=note_id, fingerprint=fp, view_date=today))
                db.session.flush()
                n.views = int(n.views or 0) + 1
                counted = True
                db.session.commit()
            except IntegrityError:
                db.session.rollback()
            return jsonify({"counted": counted, "views": int(n.views or 0)})

    except Exception as e:
        # Log detallado y 500 para detectar esquemas rotos
        current_app.logger.exception("view_note error: %s", e)
        db.session.rollback()
        return jsonify({"ok": False, "error": "view insert failed"}), 500
'''
s2 = re.sub(pat, repl, s, flags=re.S)
if s2 == s:
    # si el patrón no calzó (distintos returns), buscamos el bloque por decorador y lo sustituimos hasta el próximo @bp.
    s2 = re.sub(r'@bp\.post\("/notes/<int:note_id>/view"\)[\s\S]*?(?=\n@bp\.|\\Z)', repl, s, flags=re.S)

Path('backend/routes.py').write_text(s2, encoding='utf-8')
print("✓ routes.py parchado: _views_enabled + view_note con ON CONFLICT/rollback seguro")
PY

python -m py_compile backend/routes.py && echo "✓ Sintaxis OK"

git add backend/routes.py
git commit -m "fix(views): forzar ENABLE_VIEWS y usar INSERT ON CONFLICT + update atómico" || true
git push -u origin main
