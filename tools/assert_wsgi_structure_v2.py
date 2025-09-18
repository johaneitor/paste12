#!/usr/bin/env python3
import re, sys, pathlib

W = pathlib.Path("wsgiapp/__init__.py")
S = W.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n")

def find_block(def_pat: str):
    m = re.search(def_pat, S, re.M)
    if not m:
        return None
    ws   = m.group(1)
    base = len(ws)
    # línea del header (0-based)
    header_idx = S[:m.start()].count("\n")
    lines = S.split("\n")
    # fin del bloque por dedent (indent <= base y no vacío)
    j = header_idx + 1
    end_idx = len(lines)
    while j < len(lines):
        L = lines[j]
        if L.strip() and (len(L) - len(L.lstrip(" "))) <= base:
            end_idx = j
            break
        j += 1
    return dict(ws=ws, base=base, header=header_idx, end=end_idx, lines=lines)

# --- _app checks ---
app = find_block(r'(?m)^([ ]*)def[ ]+_app\(\s*environ\s*,\s*start_response\s*\)\s*(?:->\s*[^:]+)?\s*:\s*$')
assert app, "no encontré def _app(environ, start_response)"

lines   = app["lines"]
ws_app  = app["ws"]; base_app = app["base"]
h_app   = app["header"]; e_app = app["end"]

# busca path/method/qs (al menos path y method)
def where_assign(name: str):
    pat = re.compile(rf'^{re.escape(ws_app)}    {name}\s*=')
    for i in range(h_app+1, e_app):
        if pat.match(lines[i]): return i
    return -1

i_path   = where_assign("path")
i_method = where_assign("method")
i_qs     = where_assign("qs")

assert i_path   >= 0, "faltó asignación de 'path' dentro de _app"
assert i_method >= 0, "faltó asignación de 'method' dentro de _app"
last_assign = max(i for i in (i_path, i_method, i_qs) if i >= 0)

# busca preflight OPTIONS
i_opt = -1
pat_opt = re.compile(
    rf'^{re.escape(ws_app)}    if\s+method\s*==\s*["\']OPTIONS["\']\s*and\s*path\.startswith\(["\']/api/["\']\)\s*:\s*$'
)
for i in range(h_app+1, e_app):
    if pat_opt.match(lines[i]):
        i_opt = i
        break
assert i_opt >= 0, "no encontré handler OPTIONS (if method == \"OPTIONS\" and path.startswith(\"/api/\"))"
assert i_opt > last_assign, "handler OPTIONS aparece antes de path/method/qs (debe ir después)"

# --- _middleware (opcional pero recomendado) ---
mw = find_block(r'(?m)^([ ]*)def[ ]+_middleware\([^)]*\)\s*(?:->\s*[^:]+)?\s*:\s*$')
if mw:
    ws_mw, base_mw, h_mw, e_mw = mw["ws"], mw["base"], mw["header"], mw["end"]
    ok_return = False
    for i in range(h_mw+1, e_mw):
        L = lines[i]
        if L.strip() == "return _app" and (len(L) - len(L.lstrip(" "))) == base_mw + 4:
            ok_return = True; break
    assert ok_return, "faltó 'return _app' dentro de _middleware con indent base+4"
else:
    print("WARN: no encontré def _middleware(...); se omite chequeo de 'return _app' (OK si usás sólo _app)")

print("OK: estructura WSGI válida (preflight posicionado y return _app correcto)")
