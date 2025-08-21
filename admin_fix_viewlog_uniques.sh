#!/usr/bin/env bash
set -Eeuo pipefail

python - <<'PY'
from pathlib import Path, re
p = Path('backend/routes.py')
s = p.read_text(encoding='utf-8')

block = r'''
@bp.post("/admin/fix_viewlog_uniques")
def admin_fix_viewlog_uniques():
    """
    - Requiere X-Admin-Token == ADMIN_TOKEN (por defecto 'changeme')
    - Postgres: elimina cualquier UNIQUE/índice único sobre (note_id,fingerprint) que NO incluya view_date.
    - Asegura:
        * columna view_date
        * UNIQUE (note_id,fingerprint,view_date)
        * índices ix_view_log_note_id, ix_view_log_view_date
    """
    import os
    from sqlalchemy import text
    tok = request.headers.get("X-Admin-Token") or ""
    expected = os.getenv("ADMIN_TOKEN") or "changeme"
    if tok != expected:
        return jsonify({"ok": False, "error": "unauthorized"}), 401

    out = {"ok": True, "dialect": db.session.bind.dialect.name, "dropped": [], "created": [], "info": []}
    dialect = out["dialect"]

    def info(msg): out["info"].append(msg)

    # 0) columna view_date idempotente
    if dialect == "postgresql":
        db.session.execute(text("ALTER TABLE view_log ADD COLUMN IF NOT EXISTS view_date date"))
        db.session.execute(text("UPDATE view_log SET view_date = (created_at AT TIME ZONE 'UTC')::date WHERE view_date IS NULL"))
        info("view_date ensured/backfilled (pg)")
    else:
        try:
            db.session.execute(text("ALTER TABLE view_log ADD COLUMN view_date DATE"))
        except Exception:
            pass
        db.session.execute(text("UPDATE view_log SET view_date = date(created_at) WHERE view_date IS NULL"))
        info("view_date ensured/backfilled (sqlite/other)")

    if dialect == "postgresql":
        # 1) buscar constraints únicos sobre view_log
        cons = db.session.execute(text("""
            SELECT conname, pg_get_constraintdef(c.oid) AS def
            FROM pg_constraint c
            JOIN pg_class t ON c.conrelid=t.oid
            WHERE t.relname='view_log' AND c.contype='u'
        """)).mappings().all()

        # dropear los que sean EXACTAMENTE únicos sobre (note_id, fingerprint) sin view_date
        for row in cons:
            name = row["conname"]
            defi = (row["def"] or "").lower()
            # ejemplo de def: 'UNIQUE (note_id, fingerprint)'
            if "unique" in defi and "view_date" not in defi:
                # comprobamos que solo estén note_id y fingerprint
                cols = defi.split("(")[1].split(")")[0].replace(" ", "")
                if cols in {"note_id,fingerprint", '"note_id","fingerprint"'}:
                    db.session.execute(text(f'ALTER TABLE view_log DROP CONSTRAINT "{name}"'))
                    out["dropped"].append(f'constraint:{name}')

        # 2) buscar índices únicos
        idxs = db.session.execute(text("""
            SELECT indexname, indexdef
            FROM pg_indexes
            WHERE tablename='view_log'
        """)).mappings().all()
        for row in idxs:
            name = row["indexname"]
            defi = (row["indexdef"] or "").lower()
            # ejemplo: 'CREATE UNIQUE INDEX ... ON public.view_log USING btree (note_id, fingerprint)'
            if "unique index" in defi and "view_date" not in defi:
                # columnas entre paréntesis
                try:
                    cols = defi.split("(")[1].split(")")[0].replace(" ", "")
                except Exception:
                    cols = ""
                if cols in {"note_id,fingerprint", '"note_id","fingerprint"'}:
                    db.session.execute(text(f'DROP INDEX IF EXISTS "{name}"'))
                    out["dropped"].append(f'index:{name}')

        # 3) asegurar UNIQUE correcto (note_id,fingerprint,view_date)
        exists = db.session.execute(text("""
            SELECT conname
            FROM pg_constraint
            WHERE conrelid='view_log'::regclass AND contype='u'
              AND pg_get_constraintdef(oid) ILIKE '%unique%view_date%'
        """)).first()
        if not exists:
            db.session.execute(text('ALTER TABLE view_log ADD CONSTRAINT "uq_view_note_fp_day" UNIQUE (note_id, fingerprint, view_date)'))
            out["created"].append('constraint:uq_view_note_fp_day')

        # 4) índices
        db.session.execute(text("CREATE INDEX IF NOT EXISTS ix_view_log_note_id ON view_log (note_id)"))
        db.session.execute(text("CREATE INDEX IF NOT EXISTS ix_view_log_view_date ON view_log (view_date)"))
        out["created"] += ["index:ix_view_log_note_id", "index:ix_view_log_view_date"]

    else:
        # sqlite: índice único de 3 columnas
        db.session.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS uq_view_note_fp_day ON view_log(note_id, fingerprint, view_date)"))
        db.session.execute(text("CREATE INDEX IF NOT EXISTS ix_view_log_note_id ON view_log (note_id)"))
        db.session.execute(text("CREATE INDEX IF NOT EXISTS ix_view_log_view_date ON view_log (view_date)"))
        out["created"] += ["index:uq_view_note_fp_day","index:ix_view_log_note_id","index:ix_view_log_view_date"]

    db.session.commit()
    return jsonify(out), 200
'''

if 'def admin_fix_viewlog_uniques()' not in s:
    s += "\n" + block + "\n"
    p.write_text(s, encoding='utf-8')
    print("✓ añadido /admin/fix_viewlog_uniques")
else:
    print("• /admin/fix_viewlog_uniques ya existe")
PY

python -m py_compile backend/routes.py && echo "✓ Sintaxis OK"

git add backend/routes.py
git commit -m "chore(admin): drop uniques antiguos (note_id,fingerprint) y asegurar UNIQUE(day)" || true
git push -u origin main
