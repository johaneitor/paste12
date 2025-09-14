#!/usr/bin/env python3
import re, sys, pathlib, shutil

W = pathlib.Path("wsgiapp/__init__.py")
src = W.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n")

bak = W.with_suffix(W.suffix + ".bak_returning")
shutil.copyfile(W, bak)

changed = False

# 1) Helper (idempotente)
HELPER = r'''
# P12 RETURNING GUARD HELPER (idempotent)
def _bump_note_counter(db, note_id, col):
    # col validada por whitelist para evitar SQL injection
    if col not in ("likes","views","reports"):
        return None
    try:
        cur = db.cursor()
        sql = f"UPDATE note SET {col}=COALESCE({col},0)+1 WHERE id=%s RETURNING COALESCE(likes,0), COALESCE(views,0), COALESCE(reports,0)"
        cur.execute(sql, (note_id,))
        row = cur.fetchone()
        cur.close()
        if not row:
            try:
                db.rollback()
            except Exception:
                pass
            return None
        try:
            db.commit()
        except Exception:
            pass
        return {"likes": row[0], "views": row[1], "reports": row[2]}
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        return None
'''.strip("\n")

if "_bump_note_counter(" not in src:
    # Insertamos antes de _finish si existe, si no al final del archivo
    m = re.search(r'(?m)^\s*def\s+_finish\s*\(', src)
    if m:
        pos = m.start()
        src = src[:pos] + HELPER + "\n\n" + src[pos:]
    else:
        src = src + "\n\n" + HELPER + "\n"
    changed = True

# 2) Reemplazar secuencias de like/view/report por el helper.
# Buscamos bloques que mencionen /api/notes y el verbo, y dentro tengan un UPDATE a note.
def patch_endpoint(s, verb, col):
    # Capturamos un bloque razonable de endpoint "verbo"
    rx = re.compile(
        rf'(?ms)(\n[^\n]*/api/notes[^\n]*/{verb}[^\n]*\n)(.*?)'
        rf'(?=\n[^\n]*/api/notes|\Z)'
    )
    any_change = False
    def repl(m):
        nonlocal any_change
        head, body = m.group(1), m.group(2)
        if "_bump_note_counter(" in body:
            return m.group(0)  # ya parcheado
        if "UPDATE" not in body or "note" not in body:
            return m.group(0)  # no tocamos endpoints raros
        # Construimos un cuerpo mínimo seguro:
        new_body = re.sub(
            r'(?ms)^.*?UPDATE[^\n]*note[^\n]*\n.*?$',
            f'        data = _bump_note_counter(db, note_id, "{col}")\n'
            f'        if not data:\n'
            f'            return _json({{"ok": False, "error": "not_found"}}, status="404 Not Found")\n'
            f'        return _json({{"ok": True, "id": note_id, "likes": data["likes"], "views": data["views"], "reports": data["reports"], "deduped": False}})\n',
            body,
            count=1
        )
        if new_body != body:
            any_change = True
            return head + new_body
        return m.group(0)
    s2 = rx.sub(repl, s)
    return s2, any_change

for (verb, col) in (("like","likes"),("view","views"),("report","reports")):
    src2, did = patch_endpoint(src, verb, col)
    if did:
        src = src2
        changed = True

if not changed:
    print("Nada que parchear: helper ya estaba y endpoints ya usan RETURNING o no se encontró patrón.")
    sys.exit(0)

W.write_text(src, encoding="utf-8")
print(f"OK: parche aplicado. Backup -> {bak}")
