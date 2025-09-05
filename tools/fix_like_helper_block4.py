#!/usr/bin/env python3
import pathlib, re, sys, shutil, py_compile

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("ERROR: wsgiapp/__init__.py no existe"); sys.exit(2)

raw = W.read_text(encoding="utf-8")
s = raw.replace("\r\n","\n").replace("\r","\n").replace("\t","    ")
changed = (s != raw)

# --- 1) borrar TODAS las defs (completas o truncadas) de _json_passthrough_like ---
lines = s.split("\n")
i = 0
removed = 0
while i < len(lines):
    m = re.match(r'^([ ]*)def\s+_json_passthrough_like\s*\([^)]*\)\s*:\s*(?:#.*)?$', lines[i])
    if not m:
        i += 1
        continue
    indent = m.group(1) or ""
    base = len(indent)
    start = i
    i += 1
    # comer “cuerpo” hasta el próximo bloque al mismo nivel o menor, o EOF
    while i < len(lines):
        line = lines[i]
        if line.strip() == "":
            i += 1
            continue
        ind = len(line) - len(line.lstrip(" "))
        if ind <= base:
            break
        i += 1
    del lines[start:i]
    i = start
    removed += 1
    changed = True

s = "\n".join(lines)

# --- 2) si quedara alguna cabecera huérfana, reemplazar por stub válido (para que compile) ---
stub_pat = re.compile(r'^([ ]*)def\s+_json_passthrough_like\s*\([^)]*\)\s*:\s*$', re.M)
def _stub_repl(m):
    ind = m.group(1) or ""
    return f"{ind}def _json_passthrough_like(note_id: int):\n{ind}    pass"
s2, n_stub = stub_pat.subn(_stub_repl, s)
if n_stub:
    s = s2
    changed = True

# --- 3) asegurar UNA versión sana a nivel módulo (columna 0) ---
if not re.search(r'(?m)^def\s+_json_passthrough_like\s*\(', s):
    helper = '''
def _json_passthrough_like(note_id: int):
    """
    Helper estable: suma likes y devuelve payload normalizado.
    Idempotencia a nivel endpoint se resuelve en otras capas; esto solo hace el UPDATE.
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

# Backup + escritura
bak = W.with_suffix(".py.pre_likefix4.bak")
if not bak.exists():
    shutil.copyfile(W, bak)
W.write_text(s, encoding="utf-8")

# Gate de compilación
try:
    py_compile.compile(str(W), doraise=True)
except Exception as e:
    print("✗ py_compile aún falla:", e)
    print("Backup en:", bak)
    # contexto para inspección rápida
    ctx = W.read_text(encoding="utf-8").split("\n")
    for ln in range(315, 340):
        if ln-1 < len(ctx):
            print(f"{ln:4d}: {ctx[ln-1]}")
    sys.exit(1)
else:
    print("✓ fixed & compiled:", W)
    print("Backup en:", bak)
