#!/usr/bin/env python3
import re, sys, pathlib
W = pathlib.Path("wsgiapp/__init__.py")
src = W.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n")

helper = r'''
def _bump_counter(db, note_id:int, field:str):
    try:
        cur = db.cursor()
        cur.execute(f"UPDATE note SET {field}=COALESCE({field},0)+1 WHERE id=%s RETURNING id, COALESCE(likes,0), COALESCE(views,0), COALESCE(reports,0)", (note_id,))
        row = cur.fetchone()
        if row:
            db.commit()
            return True, {'ok': True, 'id': row[0], 'likes': row[1], 'views': row[2], 'reports': row[3], 'deduped': False}
        db.rollback()
        return False, {'ok': False, 'error': 'not_found'}
    except Exception as e:
        try: db.rollback()
        except Exception: pass
        return False, {'ok': False, 'error': 'db_error'}
'''.strip("\n")

# 1) Inserta helper si no existe
if "_bump_counter(" not in src:
    # lo pegamos luego del primer def _finish o al final del archivo
    m = re.search(r'(?m)^def[ ]+_finish\([^)]*\):.*?\n(?=def|$)', src, flags=re.S)
    if m:
        insert_at = m.end()
        src = src[:insert_at] + "\n\n" + helper + "\n\n" + src[insert_at:]
    else:
        src = src.rstrip() + "\n\n" + helper + "\n"

# 2) Reescribe like/view/report para usar _bump_counter
def patch_endpoint(s, field):
    # busca un bloque que mencione el endpoint y haga UPDATE del campo
    # y reemplaza por llamada al helper + retorno JSON/404
    # patrón tolerante para el UPDATE original
    upd = re.compile(
        rf'''(?sx)
        (def[ ]+[a-zA-Z_][\w]*\([^)]*\):[^\n]*\n    .*?/api/notes.*?{field}.*?\n)   # encabezado+ruta
        (.*?cur\s*=\s*db\.cursor\(\)\s*\n)?                                         # cursor opcional
        .*?UPDATE\s+note\s+SET\s+{field}\s*=\s*COALESCE\(\s*{field}\s*,\s*0\s*\)\s*\+\s*1\s+WHERE\s+id\s*=\s*%s.*?\n  # update
        (.*?return[^\n]*\n)                                                         # algún return final del ep
        ''')
    def repl(m):
        head = m.group(1)
        return (head +
                f"    ok,payload = _bump_counter(db, note_id, '{field}')\n"
                f"    if ok:\n"
                f"        return _json(payload)\n"
                f"    elif payload.get('error')=='not_found':\n"
                f"        return _json(payload, status='404 Not Found')\n"
                f"    return _json(payload, status='500 Internal Server Error')\n")
    return re.sub(upd, repl, s, count=1)

for field in ("likes","views","reports"):
    src = patch_endpoint(src, field)

W.write_text(src, encoding="utf-8")
print("OK: endpoints like/view/report ahora usan UPDATE..RETURNING con 404 limpio.")
