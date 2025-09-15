#!/usr/bin/env python3
import re, sys, pathlib

W = pathlib.Path("wsgiapp/__init__.py")
src = W.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n")

changed = False

HELPER = """
# BEGIN:p12_bump_helper
def _bump_counter(db, note_id: int, field: str):
    if field not in ("likes", "views", "reports"):
        return False, {"ok": False, "error": "bad_field"}
    try:
        cur = db.cursor()
        sql = (
            "UPDATE note "
            f"SET {field}=COALESCE({field},0)+1 "
            "WHERE id=%s "
            "RETURNING id, COALESCE(likes,0), COALESCE(views,0), COALESCE(reports,0)"
        )
        cur.execute(sql, (note_id,))
        row = cur.fetchone()
        cur.close()
        if not row:
            try: db.rollback()
            except Exception: pass
            return False, {"ok": False, "error": "not_found"}
        try: db.commit()
        except Exception: pass
        return True, {"ok": True, "id": row[0], "likes": row[1], "views": row[2], "reports": row[3], "deduped": False}
    except Exception:
        try: db.rollback()
        except Exception: pass
        return False, {"ok": False, "error": "db_error"}
# END:p12_bump_helper
""".strip() + "\n\n"

# 0) Asegura helper sano (elimina versiones anteriores si quedaron)
src = re.sub(r'(?ms)^# BEGIN:p12_bump_helper.*?# END:p12_bump_helper\s*', '', src)
src = re.sub(r'(?ms)^def[ \t]+_bump_counter\s*\([^)]*\):\s*\n(?:[ \t].*\n)*', '', src)

mfin = re.search(r'(?ms)^def[ \t]+_finish\s*\([^)]*\):.*?(?=^\S|^def|\Z)', src)
if mfin:
    insert_at = mfin.end()
    src = src[:insert_at] + "\n\n" + HELPER + src[insert_at:]
else:
    src = src.rstrip() + "\n\n" + HELPER

def replace_counter_block(src: str, field: str) -> tuple[str, int]:
    """
    Busca un UPDATE de 'field' y reemplaza el bloque:
      <indent>cur = db.cursor()
      <indent>cur.execute("UPDATE note SET field=COALESCE(field,0)+1 WHERE id=%s ...")
      ... (cualquier cosa) ...
      <indent>return ...
    por llamada a _bump_counter con manejo 200/404/500.

    Hace solo un reemplazo por campo (el más típico). Repetir si hubiera múltiples.
    """
    # 1) Localiza la línea del UPDATE del campo (captura indent)
    upd = re.search(
        rf'(?m)^(?P<ind>[ \t]+)cur\.execute\([^\n]*UPDATE\s+note\s+SET\s+{field}\b.*$',
        src
    )
    if not upd:
        return src, 0

    ind = upd.group('ind')
    upd_start = upd.start()

    # 2) Busca hacia atrás el "cur = db.cursor()" en la misma indent
    before = src[:upd_start]
    curm = list(re.finditer(rf'(?m)^{re.escape(ind)}cur\s*=\s*db\.cursor\(\)\s*$', before))
    if not curm:
        return src, 0
    cur_line = curm[-1].start()

    # 3) Busca hacia adelante el primer "return ..." con la misma indent
    after = src[upd.start():]
    retm = re.search(rf'(?m)^{re.escape(ind)}return[^\n]*$', after)
    if not retm:
        return src, 0
    ret_end = upd.start() + retm.end()  # índice absoluto del final de esa línea

    # 4) Construye el bloque nuevo
    new_block = (
        f"{ind}ok, payload = _bump_counter(db, note_id, '{field}')\n"
        f"{ind}if ok:\n"
        f"{ind}    return _json(payload)\n"
        f"{ind}elif payload.get('error') == 'not_found':\n"
        f"{ind}    return _json(payload, status='404 Not Found')\n"
        f"{ind}return _json(payload, status='500 Internal Server Error')\n"
    )

    # 5) Reemplaza desde la línea del cursor hasta la línea return
    new_src = src[:cur_line] + new_block + src[ret_end:]
    return new_src, 1

hits_total = 0
for fld in ("likes", "reports"):  # view ya te da 404, no lo tocamos
    src, hits = replace_counter_block(src, fld)
    hits_total += hits

pathlib.Path(W).write_text(src, encoding="utf-8")
print(f"OK: helper sano y reemplazos aplicados={hits_total} (likes/reports)")
