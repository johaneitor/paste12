#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)

def R(): return W.read_text(encoding="utf-8")
def WRT(s): W.write_text(s, encoding="utf-8")
def norm(s): return s.replace("\r\n","\n").replace("\r","\n").replace("\t","    ")

def gate():
    try:
        py_compile.compile(str(W), doraise=True)
        print("✓ py_compile OK"); return True
    except Exception as e:
        print("✗ py_compile FAIL:", e)
        tb = traceback.format_exc()
        m = re.search(r'__init__\.py, line (\d+)', tb)
        if m:
            ln = int(m.group(1)); ctx = R().splitlines()
            a = max(1, ln-35); b = min(len(ctx), ln+35)
            print(f"\n--- Ventana {a}-{b} ---")
            for k in range(a, b+1): print(f"{k:5d}: {ctx[k-1]}")
        return False

src = norm(R())
lines = src.split("\n")

# 1) localizar def _app(environ, start_response):
m_app = re.search(r'(?m)^([ ]*)def\s+_app\s*\(\s*environ\s*,\s*start_response\s*\)\s*:\s*$', src)
if not m_app:
    print("✗ no encontré 'def _app(environ, start_response):'"); sys.exit(1)
app_ws = m_app.group(1); app_base = len(app_ws)
app_hdr_idx = src[:m_app.start()].count("\n")

# 2) delimitar fin de _app por dedent
j = app_hdr_idx + 1
end_idx = len(lines)
while j < len(lines):
    L = lines[j]
    if L.strip() and (len(L) - len(L.lstrip(" "))) <= app_base:
        end_idx = j; break
    j += 1

# 3) asegurar path/method/qs (si faltan, insertarlos al inicio del cuerpo)
def find_assign(name):
    pat = re.compile(rf'^{re.escape(app_ws)}    {name}\s*=')
    for k in range(app_hdr_idx+1, end_idx):
        if pat.match(lines[k]): return k
    return None

idx_path   = find_assign("path")
idx_method = find_assign("method")
idx_qs     = find_assign("qs")

inserted = False
inject = []
if idx_path is None:
    inject.append(app_ws + '    path   = environ.get("PATH_INFO", "") or ""')
if idx_method is None:
    inject.append(app_ws + '    method = (environ.get("REQUEST_METHOD", "GET") or "GET").upper()')
if idx_qs is None:
    inject.append(app_ws + '    qs     = environ.get("QUERY_STRING", "") or ""')
if inject:
    inject.append("")  # línea en blanco
    lines[app_hdr_idx+1:app_hdr_idx+1] = inject
    end_idx += len(inject); inserted = True
    # recomputar índices de asignaciones
    src2 = "\n".join(lines)
    idx_path   = find_assign("path")   or (app_hdr_idx+1)
    idx_method = find_assign("method") or (app_hdr_idx+2)
    idx_qs     = find_assign("qs")     or (app_hdr_idx+3)

# último índice de las 3 asignaciones (punto de inserción)
last_assign_idx = max(idx for idx in (idx_path, idx_method, idx_qs) if idx is not None)

# 4) eliminar cualquier bloque preflight existente y recolocarlo tras last_assign_idx
def block_indent(i): return len(lines[i]) - len(lines[i].lstrip(" "))
pre_pat = re.compile(rf'^{re.escape(app_ws)}    if\s+method\s*==\s*["\']OPTIONS["\']\s*and\s*path\.startswith\(\s*["\']/api/["\']\s*\)\s*:\s*$')

k = app_hdr_idx + 1
removed_any = False
while k < end_idx:
    if pre_pat.match(lines[k]):
        # incluye comentario de encabezado si está justo arriba con mismo indent
        start_k = k
        if k-1 >= app_hdr_idx+1 and lines[k-1].lstrip().startswith("#") and block_indent(k-1) == app_base+4:
            start_k = k-1
        # recorta hasta dedent <= app_base+4 (o fin de _app)
        t = k + 1
        while t < end_idx:
            if lines[t].strip() and block_indent(t) <= app_base+4: break
            t += 1
        del lines[start_k:t]
        end_idx -= (t - start_k)
        removed_any = True
        k = start_k
    else:
        k += 1

# 5) insertar bloque canónico tras last_assign_idx
IND = app_ws + "    "
pre_block = [
    IND + "# Preflight CORS/OPTIONS para /api/*",
    IND + 'if method == "OPTIONS" and path.startswith("/api/"):',
    IND + '    origin = environ.get("HTTP_ORIGIN")',
    IND + '    hdrs = [',
    IND + '        ("Content-Type", "application/json; charset=utf-8"),',
    IND + '        ("Access-Control-Allow-Methods", "GET,POST,OPTIONS"),',
    IND + '        ("Access-Control-Allow-Headers", "Content-Type, Accept"),',
    IND + '        ("Access-Control-Max-Age", "600"),',
    IND + '    ]',
    IND + '    if origin:',
    IND + '        hdrs += [',
    IND + '            ("Access-Control-Allow-Origin", origin),',
    IND + '            ("Vary", "Origin"),',
    IND + '            ("Access-Control-Allow-Credentials", "true"),',
    IND + '            ("Access-Control-Expose-Headers", "Link, X-Next-Cursor, X-Summary-Applied, X-Summary-Limit"),',
    IND + '        ]',
    IND + '    start_response("204 No Content", hdrs)',
    IND + '    return [b""]',
    ""
]
lines[last_assign_idx+1:last_assign_idx+1] = pre_block
end_idx += len(pre_block)

# 6) asegurar que _middleware devuelve return _app al final (indent correcto)
src3 = "\n".join(lines)
m_mw = re.search(r'(?m)^([ ]*)def[ ]+_middleware\([^)]*\)\s*(?:->\s*[^:]+)?\s*:\s*$', src3)
if m_mw:
    mw_ws = m_mw.group(1); mw_base = len(mw_ws)
    mw_hdr_idx = src3[:m_mw.start()].count("\n")
    j = mw_hdr_idx + 1; end_mw = len(lines)
    while j < len(lines):
        L = lines[j]
        if L.strip() and (len(L) - len(L.lstrip(" "))) <= mw_base:
            end_mw = j; break
        j += 1
    has_ret = False
    for t in range(mw_hdr_idx+1, end_mw):
        if lines[t].strip() == "return _app" and (len(lines[t]) - len(lines[t].lstrip(" "))) == mw_base+4:
            has_ret = True; break
    if not has_ret:
        lines.insert(end_mw, mw_ws + "    return _app")

out = "\n".join(lines)
if out == src:
    print("OK: no había nada para cambiar")
    if not gate(): sys.exit(1)
    sys.exit(0)

bak = W.with_suffix(".py.fix_preflight_after_assignments.bak")
if not bak.exists(): shutil.copyfile(W, bak)
WRT(out)
print(f"patched: preflight tras path/method/qs | backup={bak.name}")
if not gate(): sys.exit(1)
