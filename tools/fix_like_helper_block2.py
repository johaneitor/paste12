#!/usr/bin/env python3
import pathlib, re, sys, shutil, py_compile

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("ERROR: wsgiapp/__init__.py no existe"); sys.exit(2)

txt = W.read_text(encoding="utf-8")
orig = txt
# normalizamos EOL e indent
txt = txt.replace("\r\n", "\n").replace("\r", "\n").replace("\t","    ")

# --- elimina TODAS las versiones viejas/rotas del helper (bloque o header sin cuerpo) ---
lines = txt.split("\n")
i = 0
removed_any = False
while i < len(lines):
    m = re.match(r'^([ ]*)def\s+_json_passthrough_like\s*\([^)]*\)\s*:\s*(?:#.*)?$', lines[i])
    if not m:
        i += 1
        continue
    indent = m.group(1)
    lvl = len(indent)
    start = i
    i += 1
    # consumo el cuerpo (líneas con indent > lvl, o vacías)
    while i < len(lines):
        line = lines[i].replace("\t","    ")
        if line.strip() == "":
            i += 1
            continue
        ind = len(line) - len(line.lstrip(" "))
        # si dedenta a nivel del header o menos y es un inicio top-level, corto
        if ind <= lvl and re.match(r'^(def|class|@|if |elif |else:|try:|except|finally:|from |import |#)', line.lstrip()):
            break
        i += 1
    del lines[start:i]
    i = start
    removed_any = True

txt2 = "\n".join(lines)
if removed_any and not txt2.endswith("\n"):
    txt2 += "\n"

# --- inserta helper limpio a nivel módulo si no existe ---
if "def _json_passthrough_like(" not in txt2:
    helper = '''
def _json_passthrough_like(note_id: int):
    """
    Helper estable: incrementa likes y devuelve payload normalizado.
    Seguro e idempotente; único side-effect es el UPDATE cuando aplica.
    """
    try:
        from sqlalchemy import text as _text
        with _engine().begin() as cx:
            cx.execute(
                _text("UPDATE note SET likes=COALESCE(likes,0)+1 WHERE id=:id"),
                {"id": note_id}
            )
            row = cx.execute(
                _text("SELECT id, COALESCE(likes,0) AS likes, COALESCE(views,0) AS views, COALESCE(reports,0) AS reports FROM note WHERE id=:id"),
                {"id": note_id}
            ).mappings().first()
        if not row:
            return 404, {"ok": False, "error": "not_found"}
        return 200, {"ok": True, "id": row["id"], "likes": row["likes"], "views": row["views"], "reports": row["reports"]}
    except Exception as e:
        return 500, {"ok": False, "error": str(e)}
'''.lstrip("\n")
    # inserto al final (seguro y simple)
    txt2 = txt2.rstrip() + "\n\n" + helper

bak = W.with_suffix(".py.pre_likefix.bak")
if not bak.exists():
    shutil.copyfile(W, bak)
W.write_text(txt2, encoding="utf-8")

try:
    py_compile.compile(str(W), doraise=True)
except Exception as e:
    print("✗ py_compile aún falla:", e)
    print("Backup:", bak)
    sys.exit(1)
else:
    print("✓ fixed & compiled:", W)
    print("Backup:", bak)
