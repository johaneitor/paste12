#!/usr/bin/env python3
import pathlib, re, sys, shutil, py_compile

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("ERROR: wsgiapp/__init__.py no existe"); sys.exit(2)

raw = W.read_text(encoding="utf-8")
s = raw.replace("\r\n","\n").replace("\r","\n").replace("\t","    ")
changed = (s != raw)

lines = s.split("\n")
i = 0
fixed_orphans = 0

# 1) Arreglar cabeceras huérfanas, donde sea que estén
hdr_re = re.compile(r'^([ ]*)def\s+_json_passthrough_like\s*\([^)]*\)\s*:\s*(?:#.*)?$')
while i < len(lines):
    m = hdr_re.match(lines[i])
    if not m:
        i += 1
        continue
    indent = m.group(1) or ""
    base = len(indent)
    j = i + 1
    # saltar líneas completamente vacías (permitidas antes del primer stmt)
    while j < len(lines) and lines[j].strip() == "":
        j += 1
    need_body = True
    if j < len(lines):
        ind_next = len(lines[j]) - len(lines[j].lstrip(" "))
        need_body = ind_next <= base
    if need_body:
        lines.insert(i+1, indent + "    pass  # auto-inserted to satisfy Python block")
        fixed_orphans += 1
        i += 2
        changed = True
    else:
        i = j

s = "\n".join(lines)

# 2) Asegurar helper top-level sano (si no hay uno top-level definido)
if not re.search(r'(?m)^def\s+_json_passthrough_like\s*\(', s):
    helper = '''
def _json_passthrough_like(note_id: int):
    """
    Helper estable: incrementa likes y retorna payload normalizado.
    La dedupe/seguridad vive en el guard del endpoint; esto solo hace el UPDATE.
    """
    try:
        from sqlalchemy import text as _text
        with _engine().begin() as cx:
            cx.execute(
                _text("UPDATE note SET likes = COALESCE(likes,0)+1 WHERE id=:id"),
                {"id": note_id}
            )
            row = cx.execute(
                _text("SELECT id, COALESCE(likes,0) AS likes, COALESCE(views,0) AS views, COALESCE(reports,0) AS reports FROM note WHERE id=:id"),
                {"id": note_id}
            ).mappings().first()
        if not row:
            return 404, {"ok": False, "error": "not_found"}
        return 200, {
            "ok": True, "id": row["id"],
            "likes": row["likes"], "views": row["views"], "reports": row["reports"]
        }
    except Exception as e:
        return 500, {"ok": False, "error": str(e)}
'''.lstrip("\n")
    s = s.rstrip() + "\n\n" + helper
    changed = True

if not changed:
    print("Nada que cambiar; intentando compilar…")

# Backup + write
bak = W.with_suffix(".py.fix_like5.bak")
if not bak.exists():
    shutil.copyfile(W, bak)
W.write_text(s, encoding="utf-8")

# Gate de compilación
try:
    py_compile.compile(str(W), doraise=True)
except Exception as e:
    print("✗ py_compile aún falla:", e)
    print("Backup en:", bak)
    ctx = W.read_text(encoding="utf-8").split("\n")
    for ln in range(315, 340):
        if ln-1 < len(ctx):
            print(f"{ln:4d}: {ctx[ln-1]}")
    sys.exit(1)
else:
    print(f"✓ fixed (orphans: {fixed_orphans}) & compiled OK")
    print("Backup en:", bak)
