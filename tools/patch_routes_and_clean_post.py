#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback, os

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)

def R(): return W.read_text(encoding="utf-8", errors="ignore")
def WRT(s): W.write_text(s, encoding="utf-8")

src = R().replace("\r\n","\n").replace("\r","\n").replace("\t","    ")
lines = src.split("\n")

# --- localizar def _app(environ, start_response) ---
m_app = re.search(r'(?m)^([ ]*)def[ ]+_app\s*\(\s*environ\s*,\s*start_response\s*\)\s*:\s*$', src)
if not m_app:
    print("✗ no encontré 'def _app(environ, start_response):'"); sys.exit(1)

app_ws = m_app.group(1)              # indent de la cabecera def _app
app_body_ws = app_ws + "    "        # indent del cuerpo normal (+4)
app_hdr_idx = src[:m_app.start()].count("\n")

# --- localizar fin del bloque _app por dedent (<= app_ws) ---
j = app_hdr_idx + 1
end_app = len(lines)
while j < len(lines):
    L = lines[j]
    if L.strip() and (len(L) - len(L.lstrip(" "))) <= len(app_ws):
        end_app = j
        break
    j += 1

def indent_of(s:str)->int: return len(s) - len(s.lstrip(" "))

# --- asegurar path/method/qs (insertar si faltan) ---
assign_pat = re.compile(rf'^{re.escape(app_body_ws)}(path|method|qs)\s*=')
have_path=have_method=have_qs=False
first_body = app_hdr_idx + 1
scan_limit = min(end_app, first_body+300)
for k in range(first_body, scan_limit):
    L = lines[k]
    if re.match(rf'^{re.escape(app_body_ws)}path\s*=', L):   have_path=True
    if re.match(rf'^{re.escape(app_body_ws)}method\s*=', L): have_method=True
    if re.match(rf'^{re.escape(app_body_ws)}qs\s*=', L):     have_qs=True

inserts=[]
if not have_path:   inserts.append(app_body_ws + 'path   = environ.get("PATH_INFO", "") or ""')
if not have_method: inserts.append(app_body_ws + 'method = (environ.get("REQUEST_METHOD","GET") or "GET").upper()')
if not have_qs:     inserts.append(app_body_ws + 'qs     = environ.get("QUERY_STRING","") or ""')

insert_at = first_body
if inserts:
    lines[insert_at:insert_at] = inserts + [""]
    end_app += len(inserts)+1

# recomputa índices breves post inserción
src2 = "\n".join(lines)
app_body_start = insert_at
# mueve insert_at al final de las asignaciones efectivas
last_assign_idx = insert_at - 1
for k in range(app_body_start, min(end_app, app_body_start+300)):
    if assign_pat.match(lines[k] or ""): last_assign_idx = k

# --- eliminar copias/vestigios de rutas simples si existen en el cuerpo ---
route_heads = [
    r'if\s+path\s+in\s*\(\s*"/"\s*,\s*"/index\.html"\s*\)\s*and\s*method\s*in\s*\("GET","HEAD"\)\s*:\s*$',
    r'if\s+path\s*==\s*"/terms"\s*and\s*method\s*in\s*\("GET","HEAD"\)\s*:\s*$',
    r'if\s+path\s*==\s*"/privacy"\s*and\s*method\s*in\s*\("GET","HEAD"\)\s*:\s*$',
    r'if\s+path\s*==\s*"/api/health"\s*and\s*method\s*in\s*\("GET","HEAD"\)\s*:\s*$',
    r'if\s+method\s*==\s*"OPTIONS"\s*and\s*path\.startswith\("/api/"\)\s*:\s*$',
]
route_rx = [ re.compile(rf'^[ ]*{h}', re.I) for h in route_heads ]

def cut_block(i:int, base:int)->int:
    """ borra bloque indentado que comienza en i, devuelve cuántas líneas borra """
    k = i+1
    while k < end_app:
        L = lines[k]
        if L.strip() and indent_of(L) <= base and not L.startswith(app_body_ws+" "):
            break
        k += 1
    del lines[i:k]
    return k - i

# barrido para borrar cada bloque si aparece antes de reinsertar
p = app_hdr_idx+1
removed = 0
while p < end_app:
    L = lines[p]
    for rx in route_rx:
        if rx.match(L or "") and indent_of(L)==len(app_body_ws):
            removed += cut_block(p, len(app_body_ws))
            end_app -= removed
            p -= 1
            break
    p += 1

# --- insertar bloque canónico tras las asignaciones ---
BLK = []
BLK += [
    app_body_ws + 'if path in ("/", "/index.html") and method in ("GET","HEAD"):',
    app_body_ws + '    if inner_app is None or os.environ.get("FORCE_BRIDGE_INDEX") == "1":',
    app_body_ws + '        status, headers, body = _serve_index_html()',
    app_body_ws + '        # Single-note flag injection (?id=..., ?note=...)',
    app_body_ws + '        try:',
    app_body_ws + '            from urllib.parse import parse_qs as _pq',
    app_body_ws + '            _id=None',
    app_body_ws + '            if qs:',
    app_body_ws + '                _q=_pq(qs, keep_blank_values=True)',
    app_body_ws + "                _idv=_q.get('id') or _q.get('note')",
    app_body_ws + '                if _idv and _idv[0].isdigit(): _id=_idv[0]',
    app_body_ws + '            if _id:',
    app_body_ws + '                try:',
    app_body_ws + '                    _b = body if isinstance(body,(bytes,bytearray)) else (body or b"")',
    app_body_ws + '                    _b = _b.replace(b"<body", f"<body data-single=\\"1\\" data-note-id=\\"{_id}\\"".encode("utf-8"), 1)',
    app_body_ws + '                    body = _b',
    app_body_ws + '                except Exception: pass',
    app_body_ws + '        except Exception: pass',
    app_body_ws + '        return _finish(start_response, status, headers, body, method)',
    app_body_ws + 'if path == "/terms" and method in ("GET","HEAD"):',
    app_body_ws + '    status, headers, body = _html(200, _TERMS_HTML)',
    app_body_ws + '    return _finish(start_response, status, headers, body, method)',
    app_body_ws + 'if path == "/privacy" and method in ("GET","HEAD"):',
    app_body_ws + '    status, headers, body = _html(200, _PRIVACY_HTML)',
    app_body_ws + '    return _finish(start_response, status, headers, body, method)',
    app_body_ws + 'if path == "/api/health" and method in ("GET","HEAD"):',
    app_body_ws + '    status, headers, body = _json(200, {"ok": True})',
    app_body_ws + '    return _finish(start_response, status, headers, body, method)',
    app_body_ws + 'if method == "OPTIONS" and path.startswith("/api/"):',
    app_body_ws + '    origin = environ.get("HTTP_ORIGIN")',
    app_body_ws + '    hdrs = [',
    app_body_ws + '        ("Content-Type", "application/json; charset=utf-8"),',
    app_body_ws + '        ("Access-Control-Allow-Methods", "GET,POST,OPTIONS"),',
    app_body_ws + '        ("Access-Control-Allow-Headers", "Content-Type, Accept, Authorization"),',
    app_body_ws + '        ("Access-Control-Max-Age", "86400"),',
    app_body_ws + '    ]',
    app_body_ws + '    if origin:',
    app_body_ws + '        hdrs += [("Access-Control-Allow-Origin", origin), ("Vary","Origin"), ("Access-Control-Allow-Credentials","true"), ("Access-Control-Expose-Headers","Link, X-Next-Cursor, X-Summary-Applied, X-Summary-Limit")]',
    app_body_ws + '    start_response("204 No Content", hdrs)',
    app_body_ws + '    return [b""]',
    ""
]

ins_pos = last_assign_idx + 1
lines[ins_pos:ins_pos] = BLK
end_app += len(BLK)

# --- limpiar bloque duplicado "ctype=..." si aparece tras un return en POST /api/notes ---
src3 = "\n".join(lines)
m_post = re.search(r'(?m)^([ ]*)if\s+path\s*==\s*"/api/notes"\s*and\s*method\s*==\s*"POST"\s*:\s*$', src3)
m_next_anchor = re.search(r'(?m)^([ ]*)if\s+path\.startswith\("/api/notes/"\)\s*and\s*method\s*==\s*"POST"\s*:\s*$', src3)
if m_post:
    post_ws = m_post.group(1)
    post_start = src3[:m_post.start()].count("\n")
    post_end = len(lines)
    # fin aproximado: antes del siguiente anchor o dedent <= app_ws
    if m_next_anchor:
        post_end = src3[:m_next_anchor.start()].count("\n")
    else:
        k = post_start+1
        while k < end_app:
            L = lines[k]
            if L.strip() and indent_of(L) <= len(app_ws):
                post_end = k; break
            k += 1
    # buscar un return y luego un "ctype =" (duplicado) dentro de este rango
    ret_idx = None
    for i in range(post_start+1, post_end):
        if "return _finish" in (lines[i] or ""):
            ret_idx = i
    if ret_idx is not None:
        dup_start = None
        for i in range(ret_idx+1, post_end):
            if re.match(r'^[ ]+ctype\s*=\s*environ\.get\(', lines[i] or ""):
                dup_start = i; break
        if dup_start is not None:
            # cortar hasta el siguiente return _finish o el fin del bloque POST
            j = dup_start+1
            while j < post_end and "return _finish" not in (lines[j] or ""):
                j += 1
            # incluir el return en el recorte si existe
            if j < post_end: j += 1
            del lines[dup_start:j]
            print(f"• limpiado bloque POST duplicado ({j-dup_start} líneas)")

out = "\n".join(lines)
if out == src:
    print("OK: nada que cambiar")
    # igual gate:
    try:
        py_compile.compile(str(W), doraise=True)
        print("✓ py_compile OK")
    except Exception as e:
        print("✗ py_compile FAIL:", e); sys.exit(1)
    sys.exit(0)

bak = W.with_suffix(".py.routes_canon_v4.bak")
if not bak.exists():
    shutil.copyfile(W, bak)
WRT(out)
print(f"patched: rutas canónicas + limpieza POST | backup={bak.name}")

# Gate + ventana si falla
try:
    py_compile.compile(str(W), doraise=True)
    print("✓ py_compile OK")
except Exception as e:
    print("✗ py_compile FAIL:", e)
    tb = traceback.format_exc()
    m = re.search(r'__init__\.py, line (\d+)', tb)
    if m:
        ln = int(m.group(1))
        ctx = R().splitlines()
        a = max(1, ln-30); b = min(len(ctx), ln+30)
        print(f"\n--- Contexto {a}-{b} ---")
        for i in range(a, b+1):
            print(f"{i:5d}: {ctx[i-1]}")
    sys.exit(1)
