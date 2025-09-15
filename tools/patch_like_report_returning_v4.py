#!/usr/bin/env python3
import re, sys, pathlib, subprocess

W = pathlib.Path("wsgiapp/__init__.py")
src = W.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n")

HELPER = """
def _bump_counter(db, note_id:int, field:str):
    try:
        cur = db.cursor()
        cur.execute(f\"\"\"UPDATE note
                          SET {field}=COALESCE({field},0)+1
                        WHERE id=%s
                    RETURNING id, COALESCE(likes,0), COALESCE(views,0), COALESCE(reports,0)\"\"\", (note_id,))
        row = cur.fetchone()
        if row:
            db.commit()
            return True, {'ok': True, 'id': row[0], 'likes': row[1], 'views': row[2], 'reports': row[3], 'deduped': False}
        db.rollback()
        return False, {'ok': False, 'error': 'not_found'}
    except Exception:
        try: db.rollback()
        except Exception: pass
        return False, {'ok': False, 'error': 'db_error'}
""".strip("\n")

def ensure_helper(s):
    return s if "_bump_counter(" in s else (s.rstrip() + "\n\n" + HELPER + "\n")

def patch_endpoint_block(s, endpoint_suffix, field):
    # busca función que atienda .../<id>/<endpoint_suffix> con POST
    rx = re.compile(
        rf"""(?sx)
        (^def\s+[A-Za-z_]\w*\s*\([^)]*\):\s*\n
           (?:(?:\s+).*\n)*?
           \s+method\s*=\s*['"]POST['"].*?\n
           (?:(?:\s+).*\n)*?
           \s+path\s*=\s*.*?/api/notes.*?<[^>]*>.*?/{endpoint_suffix}.*?\n
           (?:(?:\s+).*\n)*?)
        (\s*#\s*BEGIN-EP-BODY.*?\n)?   # marcador opcional
        (\s+(?:.|\n)*?\n)              # cuerpo hasta próximo def o EOF
        (?=^def|\Z)
        """, re.M)
    m = rx.search(s)
    if not m: return s, False
    head, _, body = m.groups()
    IND = "    "
    new_body = (
        f"{IND}ok,payload = _bump_counter(db, note_id, '{field}')\n"
        f"{IND}if ok:\n"
        f"{IND}{IND}return _json(payload)\n"
        f"{IND}elif payload.get('error')=='not_found':\n"
        f"{IND}{IND}return _json(payload, status='404 Not Found')\n"
        f"{IND}return _json(payload, status='500 Internal Server Error')\n"
    )
    return s.replace(head+body, head+new_body), True

orig = src
src = ensure_helper(src)
changed = False
for suffix, field in (("like","likes"),("report","reports")):
    src, did = patch_endpoint_block(src, suffix, field)
    changed = changed or did
    print(f"patch {suffix}: {'OK' if did else 'skip'}")

if changed or src != orig:
    W.write_text(src, encoding="utf-8")
    print("OK: parche aplicado")
else:
    print("Nada para cambiar")

# compila antes de salir
import py_compile
py_compile.compile(str(W), doraise=True)
print("✓ py_compile OK")
