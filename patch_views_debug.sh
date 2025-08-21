#!/usr/bin/env bash
set -Eeuo pipefail

python - <<'PY'
from pathlib import Path, re
p = Path('backend/routes.py'); s = p.read_text(encoding='utf-8')

# 1) En el handler de /view, si falla, devolver 'detail' cuando venga X-Admin-Token
s = re.sub(
r'@bp\.post\("/notes/<int:note_id>/view"\)([\s\S]*?)except Exception as e:[\s\S]*?current_app\.logger\.exception\("view_note error: %s", e\)[\s\S]*?db\.session\.rollback\(\)[\s\S]*?return jsonify\(\{"ok": False, "error": "view insert failed"\}\), 500',
r'''@bp.post("/notes/<int:note_id>/view")\1except Exception as e:
        from flask import request
        current_app.logger.exception("view_note error: %s", e)
        db.session.rollback()
        detail = str(e)
        import os
        tok = request.headers.get("X-Admin-Token") or ""
        expected = os.getenv("ADMIN_TOKEN") or "changeme"
        if tok == expected:
            return jsonify({"ok": False, "error": "view insert failed", "detail": detail}), 500
        return jsonify({"ok": False, "error": "view insert failed"}), 500''',
flags=re.S)

# 2) Endpoint: /api/admin/diag_viewlog_schema (columnas, uniques, índices)
if '/admin/diag_viewlog_schema' not in s:
    s += r'''

@bp.get("/admin/diag_viewlog_schema")
def admin_diag_viewlog_schema():
    import os
    from sqlalchemy import text
    tok = request.headers.get("X-Admin-Token") or ""
    if tok != (os.getenv("ADMIN_TOKEN") or "changeme"):
        return jsonify({"ok": False, "error": "unauthorized"}), 401
    out = {"ok": True, "dialect": (db.session.get_bind() or db.engine).dialect.name}
    if out["dialect"] == "postgresql":
        cols = db.session.execute(text("""
            SELECT column_name, data_type, is_nullable
            FROM information_schema.columns
            WHERE table_name='view_log'
            ORDER BY ordinal_position
        """)).mappings().all()
        uniques = db.session.execute(text("""
            SELECT conname, pg_get_constraintdef(oid) AS def
            FROM pg_constraint
            WHERE conrelid='view_log'::regclass AND contype='u'
        """)).mappings().all()
        idxs = db.session.execute(text("""
            SELECT indexname, indexdef
            FROM pg_indexes
            WHERE tablename='view_log'
        """)).mappings().all()
        out["columns"] = list(cols)
        out["uniques"] = list(uniques)
        out["indexes"] = list(idxs)
    else:
        out["note"] = "Non-PG dialect; inspect manually."
    return jsonify(out), 200
'''

# 3) Endpoint: /api/admin/diag_try_insert — intenta el INSERT ON CONFLICT con parámetros
if '/admin/diag_try_insert' not in s:
    s += r'''

@bp.post("/admin/diag_try_insert")
def admin_diag_try_insert():
    import os, json
    from sqlalchemy import text
    tok = request.headers.get("X-Admin-Token") or ""
    if tok != (os.getenv("ADMIN_TOKEN") or "changeme"):
        return jsonify({"ok": False, "error": "unauthorized"}), 401
    try:
        data = request.get_json(silent=True) or {}
        nid = int(data.get("note_id") or request.args.get("note_id") or 0)
        fp  = (data.get("fp") or request.args.get("fp") or "diag-fp").strip() or "diag-fp"
        vd  = _now().date()
    except Exception as e:
        return jsonify({"ok": False, "error": f"bad args: {e}"}), 400
    try:
        dialect = (db.session.get_bind() or db.engine).dialect.name
        if dialect != "postgresql":
            return jsonify({"ok": False, "error": "only for postgres"}), 400
        res = db.session.execute(db.text("""
            INSERT INTO view_log (note_id, fingerprint, view_date, created_at)
            VALUES (:nid, :fp, :vd, (NOW() AT TIME ZONE 'UTC'))
            ON CONFLICT (note_id, fingerprint, view_date) DO NOTHING
        """), {"nid": nid, "fp": fp, "vd": vd})
        rc = getattr(res, "rowcount", 0)
        db.session.commit()
        return jsonify({"ok": True, "rowcount": int(rc)}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"ok": False, "error": str(e)}), 500
'''

Path('backend/routes.py').write_text(s, encoding='utf-8')
print("✓ routes.py: debug de vistas + diagnósticos admin añadidos/actualizados")
PY

python -m py_compile backend/routes.py && echo "✓ Sintaxis OK"
git add backend/routes.py
git commit -m "chore(views,admin): exponer detalle con X-Admin-Token y diag de schema/insert" || true
git push -u origin main
