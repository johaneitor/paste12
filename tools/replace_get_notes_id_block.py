#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)

def rw(): return W.read_text(encoding="utf-8")
def norm(s: str) -> str:
    s = s.replace("\r\n","\n").replace("\r","\n")
    if "\t" in s: s = s.replace("\t","    ")
    return s

def gate():
    try:
        py_compile.compile(str(W), doraise=True)
        print("✓ py_compile OK"); return True
    except Exception as e:
        print("✗ py_compile FAIL:", e)
        tb = traceback.format_exc()
        m = re.search(r'__init__\.py, line (\d+)', tb)
        if m:
            ln = int(m.group(1))
            ctx = rw().splitlines()
            a = max(1, ln-40); b = min(len(ctx), ln+40)
            print(f"\n--- Ventana {a}-{b} ---")
            for k in range(a, b+1):
                print(f"{k:5d}: {ctx[k-1]}")
        return False

s = norm(rw())

# Localiza el bloque GET /api/notes/:id
pat_get = re.compile(r'^([ ]*)if\s+path\.startswith\(\s*[\'"]/api/notes/[\'"]\s*\)\s+and\s+method\s*==\s*[\'"]GET[\'"]\s*:\s*$', re.M)
mg = pat_get.search(s)
if not mg:
    print("✗ no encontré el bloque GET /api/notes/:id"); sys.exit(1)

ws = mg.group(1)
get_start = mg.start()
tail = s[mg.end():]

# Fin del bloque GET: antes de 'if inner_app is not None:' o 'return _app' o EOF
cands = []
m1 = re.search(r'^[ ]*if\s+inner_app\s+is\s+not\s+None\s*:\s*$', tail, re.M)
if m1: cands.append(m1.start())
m2 = re.search(r'^[ ]*return\s+_app\s*$', tail, re.M)
if m2: cands.append(m2.start())
get_end = mg.end() + (min(cands) if cands else len(tail))

tmpl = f"""{ws}if path.startswith("/api/notes/") and method == "GET":
{ws}    tail = path.removeprefix("/api/notes/")
{ws}    try:
{ws}        note_id = int(tail)
{ws}    except Exception:
{ws}        note_id = None
{ws}    if note_id:
{ws}        from sqlalchemy import text as _text
{ws}        with _engine().begin() as cx:  # type: ignore[name-defined]
{ws}            cols = _columns(cx)  # type: ignore[name-defined]
{ws}            sel = _build_select(cols, with_where=False) + " OFFSET 0"  # type: ignore[name-defined]
{ws}            row = cx.execute(_text(f"SELECT * FROM ({{sel}}) x WHERE id=:id"), {{"id": note_id, "lim": 1}}).mappings().first()
{ws}        if not row:
{ws}            status, headers, body = _json(404, {{"ok": False, "error": "not_found"}})  # type: ignore[name-defined]
{ws}        else:
{ws}            status, headers, body = _json(200, {{"ok": True, "item": _normalize_row(dict(row))}})  # type: ignore[name-defined]
{ws}        return _finish(start_response, status, headers, body, method)  # type: ignore[name-defined]
"""

new_s = s[:get_start] + tmpl + s[get_end:]
if new_s == s:
    print("OK: no cambios aplicados"); sys.exit(0)

bak = W.with_suffix(".py.replace_get_notes_block.bak")
if not bak.exists(): shutil.copyfile(W, bak)
W.write_text(new_s, encoding="utf-8")
print(f"patched: bloque GET /api/notes/:id reemplazado | backup={bak.name}")

if not gate(): sys.exit(1)
