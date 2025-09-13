#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)

def R(): return W.read_text(encoding="utf-8", errors="ignore")
def WRT(s): W.write_text(s, encoding="utf-8")

src = R().replace("\r\n","\n").replace("\r","\n")

# 1) Inyectar _finish2 robusto y reasignar _finish (sin borrar el anterior)
if "def _finish2(" not in src:
    robust = '''
def _finish2(start_response, status, headers, body, method, extra_headers=None):
    # normaliza headers
    try:
        hdrs = list(headers or [])
    except Exception:
        hdrs = []
    if extra_headers:
        try:
            hdrs.extend(extra_headers)
        except Exception:
            pass
    # body -> bytes
    if isinstance(body, (bytes, bytearray)):
        b = body
    elif body is None:
        b = b""
    else:
        try:
            b = body.encode("utf-8")
        except Exception:
            b = b""
    # Content-Type por defecto si falta
    has_ct = False
    for (k, _) in hdrs:
        if str(k).lower() == "content-type":
            has_ct = True
            break
    if not has_ct:
        ct = "application/json; charset=utf-8" if (len(b) and b[:1] in (b"{", b"[")) else "text/html; charset=utf-8"
        hdrs.append(("Content-Type", ct))
    # HEAD => sin cuerpo (pero status/headers correctos)
    if method == "HEAD":
        hdrs = [(k,v) for (k,v) in hdrs if str(k).lower() != "content-length"]
        start_response(status, hdrs)
        return [b""]
    # Content-Length consistente
    hdrs = [(k,v) for (k,v) in hdrs if str(k).lower() != "content-length"]
    hdrs.append(("Content-Length", str(len(b))))
    start_response(status, hdrs)
    return [b]
# Fuerza alias
_finish = _finish2
'''
    # insertamos al final del archivo
    src += "\n" + robust

# 2) Inyectar guard de index tras path/method/qs dentro de _app
#    - idempotente: si ya existe el marcador, no duplica
if "# P12: index guard v1" not in src:
    m_app = re.search(r'(?m)^([ ]*)def[ ]+_app\s*\(\s*environ\s*,\s*start_response\s*\)\s*:\s*$', src)
    if not m_app:
        print("✗ no encontré def _app(environ, start_response)"); sys.exit(1)
    app_ws = m_app.group(1)
    body_indent = app_ws + "    "
    lines = src.split("\n")
    hdr_idx = src[:m_app.start()].count("\n")
    # localizar asignaciones path/method/qs
    first_body = None
    last_assign = None
    for i in range(hdr_idx+1, min(len(lines), hdr_idx+400)):
        L = lines[i]
        if first_body is None and L.strip():
            first_body = i
        if re.match(r'^\s*path\s*=\s*environ\.get\(', L): last_assign = i
        if re.match(r'^\s*method\s*=\s*environ\.get\(', L): last_assign = i
        if re.match(r'^\s*qs\s*=\s*environ\.get\(', L): last_assign = i
        # fin del bloque de _app por dedent
        if L.strip() and not L.startswith(body_indent) and i > first_body:
            break
    if last_assign is None:
        # si no están, insertamos antes de lo que haya
        insert_at = first_body if first_body is not None else (hdr_idx+1)
        inject_assign = [
            body_indent + 'path   = environ.get("PATH_INFO", "") or ""',
            body_indent + 'method = (environ.get("REQUEST_METHOD","GET") or "GET").upper()',
            body_indent + 'qs     = environ.get("QUERY_STRING", "") or ""',
            ""
        ]
        lines[insert_at:insert_at] = inject_assign
        last_assign = insert_at + 2
    # bloque guard
    guard = [
        body_indent + "# P12: index guard v1 — sirve index y bandera single-note",
        body_indent + 'if path in ("/", "/index.html") and method in ("GET","HEAD"):',
        body_indent + '    try:',
        body_indent + '        status, headers, body = _serve_index_html()',
        body_indent + '    except Exception:',
        body_indent + '        status, headers, body = "200 OK", [("Content-Type","text/html; charset=utf-8")], b"<!doctype html><meta charset=\\"utf-8\\"><title>Paste12</title><body><h1>Paste12</h1></body>"',
        body_indent + '    # bandera data-single si viene ?id= o ?note=',
        body_indent + '    try:',
        body_indent + '        from urllib.parse import parse_qs as _pq',
        body_indent + '        _q = _pq(qs, keep_blank_values=True) if qs else {}',
        body_indent + '        _idv = _q.get("id") or _q.get("note")',
        body_indent + '        if _idv and _idv[0].isdigit():',
        body_indent + '            _b = body if isinstance(body,(bytes,bytearray)) else (body or b"")',
        body_indent + '            body = _b.replace(b"<body", f\'<body data-single="1" data-note-id="{_idv[0]}"\'.encode("utf-8"), 1)',
        body_indent + '    except Exception:',
        body_indent + '        pass',
        body_indent + '    return _finish(start_response, status, headers, body, method)',
        ""
    ]
    insert_at = last_assign + 1
    lines[insert_at:insert_at] = guard
    src = "\n".join(lines)

bak = W.with_suffix(".py.finish_guard.bak")
if not bak.exists():
    shutil.copyfile(W, bak)
WRT(src)

# Gate de compilación con ventana contextual si falla
try:
    py_compile.compile(str(W), doraise=True)
    print("✓ compile OK | backup=", bak.name)
except Exception as e:
    print("✗ py_compile FAIL:", e)
    tb = traceback.format_exc()
    m = re.search(r'__init__\.py, line (\d+)', tb)
    if m:
        ln = int(m.group(1))
        ctx = R().splitlines()
        a = max(1, ln-25); b = min(len(ctx), ln+25)
        print(f"\n--- Contexto {a}-{b} ---")
        for i in range(a, b+1):
            print(f"{i:5d}: {ctx[i-1]}")
    sys.exit(1)
