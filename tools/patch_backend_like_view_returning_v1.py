#!/usr/bin/env python3
import re, sys, pathlib, py_compile, shutil

W = pathlib.Path("wsgiapp/__init__.py")
src = W.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n")

bak = W.with_suffix(".likeview_returning.bak")
if not bak.exists():
    shutil.copyfile(W, bak)

def patch_one(sql_kw, json_key):
    # Busca la secuencia UPDATE ... WHERE id=%s y reemplaza por UPDATE ... RETURNING
    # y luego agrega manejo de fetchone() is None -> 404
    # Regex tolerante al espacio y comillas
    upd_rx = re.compile(
        rf"""(?sx)
        (cur\s*=\s*db\.cursor\(\)\s*.*?             # cursor
         cur\.execute\(\s*['"]\s*UPDATE\s+note\s+SET\s+{sql_kw}\s*=\s*COALESCE\(\s*{sql_kw}\s*,\s*0\)\s*\+\s*1\s*WHERE\s+id\s*=\s*%s\s*['"]\s*,\s*\(note_id,\)\s*\)\s*.*?
         db\.commit\(\)\s*.*?                       # commit actual
         cur\.close\(\)\s*.*?                       # close
         return\s+_json\(\{{\s*'ok'\s*:\s*True,.*?['"]{json_key}['"]\s*:\s*[0-9]+.*?)  # return ok
        )
        """)
    m = upd_rx.search(src)
    if not m:
        return None

    block = m.group(1)
    # 1) RETURNING + fetchone
    block2 = re.sub(
        r"UPDATE\s+note\s+SET\s+"+sql_kw+r"\s*=\s*COALESCE\(\s*"+sql_kw+r"\s*,\s*0\)\s*\+\s*1\s*WHERE\s+id\s*=\s*%s",
        r"UPDATE note SET "+sql_kw+r"=COALESCE("+sql_kw+r",0)+1 WHERE id=%s RETURNING "+sql_kw,
        block,
        flags=re.S
    )
    # 2) insertar fetchone + 404 antes del commit
    block2 = re.sub(
        r"(cur\.execute\([^\n]+\)\s*)",
        r"\1\n        row = cur.fetchone()\n        if not row:\n            db.rollback()\n            cur.close()\n            return _json({'ok': False, 'error': 'not_found'}, status='404 Not Found')\n",
        block2,
        flags=re.S
    )
    # 3) asegurar commit después del 404 check (ya está), no tocamos el JSON final
    return src.replace(block, block2, 1)

new_src = src
for kw, key in (("likes","likes"), ("views","views"), ("reports","reports")):
    patched = patch_one(kw, key)
    if patched:
        new_src = patched
        src = patched

if new_src == W.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n"):
    print("Nada que parchear (no se encontró patrón UPDATE likes/views/reports).")
    sys.exit(0)

W.write_text(new_src, encoding="utf-8")
try:
    py_compile.compile(str(W), doraise=True)
    print("✓ parche RETURNING aplicado y compilado. Backup:", bak.name)
except Exception as e:
    shutil.copyfile(bak, W)  # rollback a backup
    print("✗ compile FAIL, restaurado backup:", e)
    sys.exit(1)
