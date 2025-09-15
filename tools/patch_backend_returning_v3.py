#!/usr/bin/env python3
import re, sys, pathlib

W = pathlib.Path("wsgiapp/__init__.py")
s = W.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n")

changed = False

# ===== Helper limpio y bien indentado =====
helper = """
# BEGIN:p12_bump_helper
def _bump_counter(db, note_id: int, field: str):
    # Seguridad mínima: solo estos campos son válidos
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
            try:
                db.rollback()
            except Exception:
                pass
            return False, {"ok": False, "error": "not_found"}
        try:
            db.commit()
        except Exception:
            pass
        return True, {
            "ok": True,
            "id": row[0],
            "likes": row[1],
            "views": row[2],
            "reports": row[3],
            "deduped": False,
        }
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        return False, {"ok": False, "error": "db_error"}
# END:p12_bump_helper
""".strip() + "\n\n"

# Quitar versiones viejas del helper si quedara alguna
s = re.sub(r'(?ms)^# BEGIN:p12_bump_helper.*?# END:p12_bump_helper\s*', '', s)
s = re.sub(r'(?ms)^def[ \t]+_bump_counter\s*\([^)]*\):\s*\n(?:[ \t].*\n)*', '', s)

# Insertar helper después de _finish o al final
m = re.search(r'(?ms)^def[ \t]+_finish\s*\([^)]*\):.*?(?=^\S|^def|\Z)', s)
if m:
    insert_at = m.end()
    s = s[:insert_at] + "\n\n" + helper + s[insert_at:]
else:
    s = s.rstrip() + "\n\n" + helper

# ===== Parche “best effort” para like/report/views =====
# Estrategia: detectar UPDATE ... SET <campo>=COALESCE(<campo>,0)+1 WHERE id=%s
# y envolver la sección con una llamada a _bump_counter. Si no matchea, no rompemos nada.

def patch_field(s, field):
    # Buscamos un bloque que contenga el UPDATE de ese campo.
    # Capturamos el encabezado de la función/bloque previo, y reemplazamos por llamada al helper.
    rx = re.compile(
        rf"(?ms)"                                  # multi-line, dotall
        rf"(^[ \t]*def[ \t]+\w+\([^)]*\):\s*\n"    # inicio de una def (con indent 0), línea a línea
        rf"(?:[ \t].*\n)+?"                        # cuerpo antes del update
        rf"[ \t]*cur\s*=\s*db\.cursor\(\)\s*\n"    # apertura de cursor
        rf"[ \t]*cur\.execute\(\s*['\"]\s*UPDATE\s+note\s+SET\s+{field}\s*=\s*COALESCE\(\s*{field}\s*,\s*0\s*\)\s*\+\s*1\s+WHERE\s+id\s*=\s*%s",
        re.M
    )
    def _repl(m):
        head = m.group(0)
        indent = ""
        # calcular indent de la def
        mdef = re.match(r'^([ \t]*)def', m.group(0))
        if mdef:
            indent = mdef.group(1)
        # inyección: volver al principio del bloque e interceptar con helper
        # Para ser simples, sustituimos desde el cursor/execute en adelante por la llamada centralizada.
        sub = re.sub(
            rf"(?ms)[ \t]*cur\s*=\s*db\.cursor\(\)\s*\n[ \t]*cur\.execute\([^\n]*\n",
            f"{indent}    ok, payload = _bump_counter(db, note_id, '{field}')\n"
            f"{indent}    if ok:\n"
            f"{indent}        return _json(payload)\n"
            f"{indent}    elif payload.get('error') == 'not_found':\n"
            f"{indent}        return _json(payload, status='404 Not Found')\n"
            f"{indent}    return _json(payload, status='500 Internal Server Error')\n",
            head,
            count=1,
        )
        return sub
    s2, n = rx.subn(_repl, s, count=1)
    return s2, n

total_hits = 0
for fld in ("likes", "reports", "views"):
    s, n = patch_field(s, fld)
    total_hits += n

W.write_text(s, encoding="utf-8")
msg = "OK: helper insertado; " + (f"parches aplicados={total_hits}" if total_hits else "no se detectaron UPDATEs a reescribir (solo helper)")
print(msg)
