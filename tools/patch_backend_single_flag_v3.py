#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile

W = pathlib.Path("wsgiapp/__init__.py")
src = W.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n")

bak = W.with_suffix(".singleflag_v3.bak")
if not bak.exists():
    shutil.copyfile(W, bak)

changed = False

# 1) helper idempotente
if "_inject_single_attr(" not in src:
    helper = '''
def _inject_single_attr(body, nid):
    try:
        b = body if isinstance(body, (bytes, bytearray)) else (body or b"")
        if b:
            return b.replace(b"<body", f'<body data-single="1" data-note-id="{nid}"'.encode("utf-8"), 1)
    except Exception:
        pass
    return body
'''
    # intenta inyectar tras _finish, o al final del módulo
    mfin = re.search(r'(?m)^def[ ]+_finish\(', src)
    if mfin:
        insert_at = src.find("\n", mfin.end()) + 1
        src = src[:insert_at] + helper + src[insert_at:]
    else:
        src = src + "\n" + helper
    changed = True

# 2) ubicar la asignación del index html y añadir inyección justo después
# buscamos la línea: status, headers, body = _serve_index_html()
m = re.search(r'(?m)^([ ]*)status,\s*headers,\s*body\s*=\s*_serve_index_html\(\)\s*$', src)
if m and "data-single" not in src:
    ws = m.group(1)  # indent del bloque dentro de _app
    inj = (
        f"{ws}# bandera single-note si viene ?id= o ?note=\n"
        f"{ws}try:\n"
        f"{ws}    from urllib.parse import parse_qs as _pq\n"
        f"{ws}    _q = _pq(qs, keep_blank_values=True) if qs else {{}}\n"
        f"{ws}    _idv = _q.get('id') or _q.get('note')\n"
        f"{ws}    if _idv and _idv[0].isdigit():\n"
        f"{ws}        body = _inject_single_attr(body, _idv[0])\n"
        f"{ws}except Exception:\n"
        f"{ws}    pass\n"
    )
    pos = m.end()
    src = src[:pos] + "\n" + inj + src[pos:]
    changed = True

if not changed:
    print("OK: single-flag ya presente o no hizo falta parchear")
else:
    W.write_text(src, encoding="utf-8")
    try:
        py_compile.compile(str(W), doraise=True)
        print("✓ backend single-flag v3 aplicado | backup=", bak.name)
    except Exception as e:
        print("✗ py_compile FAIL:", e); sys.exit(1)
