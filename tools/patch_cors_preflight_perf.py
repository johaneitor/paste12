#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback
W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists(): print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)

def R(): return W.read_text(encoding="utf-8")
def WRT(s): W.write_text(s, encoding="utf-8")

src = R().replace("\r\n","\n").replace("\r","\n").replace("\t","    ")

# Localiza def _app(...) y su indent
m_app = re.search(r'(?m)^([ ]*)def[ ]+_app\s*\(\s*environ\s*,\s*start_response\s*\)\s*:\s*$', src)
if not m_app: print("✗ no encontré def _app(...):"); sys.exit(1)
app_ws = m_app.group(1)
app_base = len(app_ws)
start = m_app.end()
# hallamos fin de _app por dedent
lines = src.split("\n")
app_line0 = src[:m_app.start()].count("\n")
j = app_line0 + 1
end = len(lines)
while j < len(lines):
    L = lines[j]
    if L.strip() and (len(L) - len(L.lstrip(" "))) <= app_base:
        end = j; break
    j += 1

# Buscamos el bloque preflight existente
pre_start = None
for k in range(app_line0+1, end):
    L = lines[k]
    if re.match(rf'^{re.escape(app_ws)}    if\s+method\s*==\s*"OPTIONS"\s*and\s*path\.startswith\("/api/"\)\s*:\s*$', L):
        pre_start = k; break

if pre_start is None:
    print("✗ no encontré bloque OPTIONS dentro de _app; nada que optimizar (ya debe estar atendido por otra capa).")
    sys.exit(0)

# Delimitar el bloque OPTIONS hasta dedent <= app_base+4
k = pre_start + 1
while k < end:
    L = lines[k]
    if L.strip() and (len(L) - len(L.lstrip(" "))) <= app_base + 4:
        break
    k += 1
pre_end = k

block = lines[pre_start:pre_end]
txt = "\n".join(block)

changed = False

# 1) Max-Age -> 86400
txt2 = re.sub(r'("Access-Control-Max-Age",\s*")\d+(")',
              r'\g<1>86400\2', txt)
if txt2 != txt:
    changed = True
    txt = txt2

# 2) Echo de Access-Control-Request-Headers
# Si no existe manejo del header de request, lo añadimos
if "Access-Control-Request-Headers" not in txt:
    IND = app_ws + "        "
    inject = [
        IND + 'req_hdrs = environ.get("HTTP_ACCESS_CONTROL_REQUEST_HEADERS")',
        IND + 'if req_hdrs:',
        IND + '    hdrs = [(k,v) for (k,v) in hdrs if k.lower() != "access-control-allow-headers"] + [("Access-Control-Allow-Headers", req_hdrs)]',
    ]
    # Insertamos justo antes de start_response("204 No Content", hdrs)
    lines_pre = txt.split("\n")
    for idx in range(len(lines_pre)):
        if 'start_response("204 No Content", hdrs)' in lines_pre[idx]:
            lines_pre[idx:idx] = inject
            changed = True
            txt = "\n".join(lines_pre)
            break

# Reemplazar bloque si hubo cambios
if changed:
    new_lines = lines[:pre_start] + txt.split("\n") + lines[pre_end:]
    out = "\n".join(new_lines)
    bak = W.with_suffix(".py.patch_cors_preflight_perf.bak")
    if not bak.exists(): shutil.copyfile(W, bak)
    WRT(out)
    print(f"patched: preflight CORS optimizado | backup={bak.name}")
else:
    print("OK: preflight ya optimizado (sin cambios)")

# Gate
try:
    py_compile.compile(str(W), doraise=True)
    print("✓ py_compile OK")
except Exception as e:
    print("✗ py_compile FAIL:", e)
    tb = traceback.format_exc(); print(tb)
    sys.exit(1)
