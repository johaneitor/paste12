#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)

def R(): return W.read_text(encoding="utf-8", errors="ignore")
def WRT(s): W.write_text(s, encoding="utf-8")

src = R().replace("\r\n","\n").replace("\r","\n").replace("\t","    ")
lines = src.split("\n")

# 1) localiza def _app(environ, start_response):
m_app = re.search(r'(?m)^([ ]*)def\s+_app\s*\(\s*environ\s*,\s*start_response\s*\)\s*:\s*$', src)
if not m_app:
    print("✗ no encontré 'def _app(environ, start_response):'"); sys.exit(1)
app_ws = m_app.group(1)
app_base = len(app_ws)
app_hdr = src[:m_app.start()].count("\n")

# 2) encuentra asignaciones path/method/qs para fijar el indent "body"
body_ws = None
assign_idxs = []
for k in range(app_hdr+1, min(app_hdr+300, len(lines))):
    L = lines[k]
    if not L.strip(): continue
    if re.match(r'^[ ]*path\s*=\s*environ\.get\(', L): assign_idxs.append(k)
    if re.match(r'^[ ]*method\s*=\s*environ\.get\(', L): assign_idxs.append(k)
    if re.match(r'^[ ]*qs\s*=\s*environ\.get\(', L): assign_idxs.append(k)
if assign_idxs:
    body_ws = re.match(r'^([ ]*)', lines[assign_idxs[0]]).group(1)
    insert_after = max(assign_idxs)
else:
    # si no las ve, las insertamos tras la cabecera
    body_ws = app_ws + "    "
    insert_after = app_hdr
    inject = [
        body_ws + 'path   = environ.get("PATH_INFO", "") or ""',
        body_ws + 'method = (environ.get("REQUEST_METHOD", "GET") or "GET").upper()',
        body_ws + 'qs     = environ.get("QUERY_STRING", "") or ""',
        ""
    ]
    lines[insert_after+1:insert_after+1] = inject
    insert_after += len(inject)

# 3) recorta cualquier bloque previo conflictivo entre insert_after y antes de /api/notes o /api/deploy-stamp
cut_start = None
pat_any = re.compile(r'^[ ]*if\s+path\s+in\s*\(\s*"/"\s*,\s*"/index\.html"\s*\)\s*and|^[ ]*if\s+path\s*==\s*"/terms"|^[ ]*if\s+path\s*==\s*"/privacy"|^[ ]*if\s+path\s*==\s*"/api/health"|^[ ]*if\s+method\s*==\s*"OPTIONS"\s*and\s*path\.startswith\("/api/"\)\s*:', re.I)
for k in range(insert_after+1, min(insert_after+500, len(lines))):
    if pat_any.match(lines[k] or ""):
        cut_start = k
        break

cut_end = None
if cut_start is not None:
    for k in range(cut_start, min(cut_start+800, len(lines))):
        L = lines[k]
        if re.search(r'/api/notes\b', L) or re.search(r'/api/deploy-stamp\b', L):
            cut_end = k
            break
# si encontramos región conflictiva, elimínala
if cut_start is not None and cut_end is not None and cut_end > cut_start:
    del lines[cut_start:cut_end]
elif cut_start is not None and cut_end is None:
    # corta hasta justo antes del final del cuerpo de _app (dedent a <= app_base)
    j = cut_start
    while j < len(lines):
        L = lines[j]
        if L.strip() and (len(L) - len(L.lstrip(" "))) <= app_base:
            break
        j += 1
    del lines[cut_start:j]

# 4) inserta bloque canónico (rutas básicas + preflight) inmediatamente después de asignaciones
IND = body_ws
BLK = [
    IND + '# Home / index (+ single-note flag cuando viene ?id=)',
    IND + 'if path in ("/", "/index.html") and method in ("GET","HEAD"):',
    IND + '    if inner_app is None or os.environ.get("FORCE_BRIDGE_INDEX") == "1":',
    IND + '        status, headers, body = _serve_index_html()',
    IND + '        # Inyección de modo single-note si viene ?id= en la query',
    IND + '        try:',
    IND + '            from urllib.parse import parse_qs as _pq',
    IND + '            _id = None',
    IND + '            if qs:',
    IND + '                _q = _pq(qs, keep_blank_values=True)',
    IND + '                _idv = _q.get("id") or _q.get("note")',
    IND + '                if _idv and _idv[0].isdigit():',
    IND + '                    _id = _idv[0]',
    IND + '            if _id:',
    IND + '                try:',
    IND + '                    _b = body if isinstance(body, (bytes, bytearray)) else (body or b"")',
    IND + '                    _b = _b.replace(b"<body", f"<body data-single=\\"1\\" data-note-id=\\"{_id}\\"".encode("utf-8"), 1)',
    IND + '                    body = _b',
    IND + '                except Exception:',
    IND + '                    pass',
    IND + '        except Exception:',
    IND + '            pass',
    IND + '        return _finish(start_response, status, headers, body, method)',
    "",
    IND + 'if path == "/terms" and method in ("GET","HEAD"):',
    IND + '    status, headers, body = _html(200, _TERMS_HTML)',
    IND + '    return _finish(start_response, status, headers, body, method)',
    IND + 'if path == "/privacy" and method in ("GET","HEAD"):',
    IND + '    status, headers, body = _html(200, _PRIVACY_HTML)',
    IND + '    return _finish(start_response, status, headers, body, method)',
    IND + 'if path == "/api/health" and method in ("GET","HEAD"):',
    IND + '    status, headers, body = _json(200, {"ok": True})',
    IND + '    return _finish(start_response, status, headers, body, method)',
    "",
    IND + '# Preflight CORS/OPTIONS para /api/*',
    IND + 'if method == "OPTIONS" and path.startswith("/api/"):',
    IND + '    origin = environ.get("HTTP_ORIGIN")',
    IND + '    hdrs = [',
    IND + '        ("Content-Type", "application/json; charset=utf-8"),',
    IND + '        ("Access-Control-Allow-Methods", "GET,POST,OPTIONS"),',
    IND + '        ("Access-Control-Allow-Headers", "Content-Type, Accept, Authorization"),',
    IND + '        ("Access-Control-Max-Age", "86400"),',
    IND + '    ]',
    IND + '    if origin:',
    IND + '        hdrs += [',
    IND + '            ("Access-Control-Allow-Origin", origin),',
    IND + '            ("Vary", "Origin"),',
    IND + '            ("Access-Control-Allow-Credentials", "true"),',
    IND + '            ("Access-Control-Expose-Headers", "Link, X-Next-Cursor, X-Summary-Applied, X-Summary-Limit"),',
    IND + '        ]',
    IND + '    req_hdrs = environ.get("HTTP_ACCESS_CONTROL_REQUEST_HEADERS")',
    IND + '    if req_hdrs:',
    IND + '        hdrs = [(k,v) for (k,v) in hdrs if k.lower() != "access-control-allow-headers"] + [("Access-Control-Allow-Headers", req_hdrs)]',
    IND + '    start_response("204 No Content", hdrs)',
    IND + '    return [b""]',
    ""
]
out = "\n".join(lines[:insert_after+1] + BLK + lines[insert_after+1:])
if out == src:
    print("OK: nada que cambiar")
else:
    bak = W.with_suffix(".py.routes_canon_v3.bak")
    if not bak.exists():
        shutil.copyfile(W, bak)
    WRT(out)
    print(f"patched: bloque de rutas canonizado | backup={bak.name}")

# 5) gate de compilación con ventana si falla
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
