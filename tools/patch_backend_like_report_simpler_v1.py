#!/usr/bin/env python3
import re, sys
from pathlib import Path

W = Path("wsgiapp/__init__.py")
src = W.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n")

HELPER = (
    "# BEGIN:p12_bump_helper\n"
    "def _bump_counter(db, note_id: int, field: str):\n"
    "    if field not in (\"likes\", \"views\", \"reports\"):\n"
    "        return False, {\"ok\": False, \"error\": \"bad_field\"}\n"
    "    try:\n"
    "        cur = db.cursor()\n"
    "        sql = (\n"
    "            \"UPDATE note \"\n"
    "            f\"SET {field}=COALESCE({field},0)+1 \"\n"
    "            \"WHERE id=%s \"\n"
    "            \"RETURNING id, COALESCE(likes,0), COALESCE(views,0), COALESCE(reports,0)\"\n"
    "        )\n"
    "        cur.execute(sql, (note_id,))\n"
    "        row = cur.fetchone()\n"
    "        cur.close()\n"
    "        if not row:\n"
    "            try: db.rollback()\n"
    "            except Exception: pass\n"
    "            return False, {\"ok\": False, \"error\": \"not_found\"}\n"
    "        try: db.commit()\n"
    "        except Exception: pass\n"
    "        return True, {\"ok\": True, \"id\": row[0], \"likes\": row[1], \"views\": row[2], \"reports\": row[3], \"deduped\": False}\n"
    "    except Exception:\n"
    "        try: db.rollback()\n"
    "        except Exception: pass\n"
    "        return False, {\"ok\": False, \"error\": \"db_error\"}\n"
    "# END:p12_bump_helper\n"
    "\n"
)

# 0) Limpia helpers anteriores y asegura uno sano
src = re.sub(r'(?ms)^# BEGIN:p12_bump_helper.*?# END:p12_bump_helper\s*', '', src)
src = re.sub(r'(?ms)^def[ \t]+_bump_counter\s*\([^)]*\):\s*\n(?:[ \t].*\n)*', '', src)

mfin = re.search(r'(?ms)^def[ \t]+_finish\s*\([^)]*\):.*?(?=^\S|^def|\Z)', src)
if mfin:
    insert_at = mfin.end()
    src = src[:insert_at] + "\n\n" + HELPER + src[insert_at:]
else:
    src = src.rstrip() + "\n\n" + HELPER

def replace_counter_block(s: str, field: str) -> tuple[str, int]:
    """
    Reemplaza el bloque que hace UPDATE de `field` en el endpoint (like/report)
    por una llamada a _bump_counter con manejo 200/404/500.

    Estrategia:
      - Detecta línea con cur.execute(... UPDATE ... field ...)
      - Busca hacia atrás el 'cur = db.cursor()' con la misma indentación
      - Busca hacia adelante el siguiente 'return ...' con esa indentación
      - Sustituye ese rango por el bloque seguro
    """
    # 1) línea del UPDATE (case-insensitive, SQL puede estar muy variado)
    upd = re.search(
        rf'(?mi)^(?P<ind>[ \t]+)cur\.execute\([^\n]*update[ \t]+note[ \t]+set[ \t]+{field}\b.*$',
        s
    )
    if not upd:
        return s, 0

    ind = upd.group('ind')
    upd_start = upd.start()

    # 2) cursor anterior con misma indent
    before = s[:upd_start]
    curm = list(re.finditer(rf'(?m)^{re.escape(ind)}cur\s*=\s*db\.cursor\(\)\s*$', before))
    if not curm:
        return s, 0
    cur_line = curm[-1].start()

    # 3) siguiente return con misma indent
    after = s[upd.start():]
    retm = re.search(rf'(?m)^{re.escape(ind)}return[^\n]*$', after)
    if not retm:
        return s, 0
    ret_end = upd.start() + retm.end()

    # 4) bloque nuevo
    new_block = (
        f"{ind}ok, payload = _bump_counter(db, note_id, '{field}')\n"
        f"{ind}if ok:\n"
        f"{ind}    return _json(payload)\n"
        f"{ind}elif payload.get('error') == 'not_found':\n"
        f"{ind}    return _json(payload, status='404 Not Found')\n"
        f"{ind}return _json(payload, status='500 Internal Server Error')\n"
    )

    # 5) reemplazo
    new_s = s[:cur_line] + new_block + s[ret_end:]
    return new_s, 1

hits_total = 0
for fld in ("likes", "reports"):  # 'view' ya está bien, no lo tocamos
    src, hits = replace_counter_block(src, fld)
    hits_total += hits

W.write_text(src, encoding="utf-8")
print(f"OK: helper sano y reemplazos aplicados={hits_total} (likes/reports)")
