#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)

def norm(s: str) -> str:
    s = s.replace("\r\n","\n").replace("\r","\n")
    return s.replace("\t","    ")

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
            ctx = W.read_text(encoding="utf-8").splitlines()
            a = max(1, ln-35); b = min(len(ctx), ln+35)
            print(f"\n--- Ventana {a}-{b} ---")
            for k in range(a, b+1):
                print(f"{k:5d}: {ctx[k-1]}")
        return False

src = norm(W.read_text(encoding="utf-8"))
lines = src.split("\n")

# 1) localizar def _middleware(...) (con o sin -> retorno)
mw_hdr = re.search(r'(?m)^([ ]*)def[ ]+_middleware\([^)]*\)\s*(?:->\s*[^:]+)?\s*:\s*$', src)
if not mw_hdr:
    print("✗ no encontré 'def _middleware(...)'"); sys.exit(1)
mw_ws = mw_hdr.group(1); mw_base = len(mw_ws)
mw_hdr_idx = src[:mw_hdr.start()].count("\n")

# quitar 'pass' suelto inmediatamente tras el header, si existe
i = mw_hdr_idx + 1
while i < len(lines) and lines[i].strip() == "":
    i += 1
if i < len(lines) and lines[i].strip() == "pass":
    del lines[i]

# recomputar offsets
src2 = "\n".join(lines)
mw_hdr = re.search(r'(?m)^([ ]*)def[ ]+_middleware\([^)]*\)\s*(?:->\s*[^:]+)?\s*:\s*$', src2)
mw_ws = mw_hdr.group(1); mw_base = len(mw_ws)
mw_hdr_idx = src2[:mw_hdr.start()].count("\n")

# hallar fin del bloque _middleware por dedent
j = mw_hdr_idx + 1
end_idx = len(lines)
while j < len(lines):
    L = lines[j]
    if L.strip() and (len(L) - len(L.lstrip(" "))) <= mw_base and not L.startswith(mw_ws + " "):
        end_idx = j
        break
    j += 1

# 2) localizar def _app(...) dentro de _middleware
block = lines[mw_hdr_idx+1:end_idx]
off = mw_hdr_idx + 1
app_m = None
for k, L in enumerate(block):
    m = re.match(r'^([ ]*)def\s+_app\s*\(\s*environ\s*,\s*start_response\s*\)\s*:\s*$', L)
    if m:
        app_m = (off + k, m.group(1))
        break
if not app_m:
    print("✗ no encontré 'def _app(environ, start_response):' dentro de _middleware")
    sys.exit(1)
app_hdr_idx, app_ws = app_m
app_base = len(app_ws)

# 3) buscar las líneas de path/method/qs para insertar tras ellas
# (buscamos el 'qs =' con el mismo indent que el cuerpo de _app)
k = app_hdr_idx + 1
qs_idx = None
while k < end_idx:
    L = lines[k]
    if L.strip()=="":
        k += 1; continue
    ind = len(L) - len(L.lstrip(" "))
    if ind <= app_base:  # dedent => fin de _app
        break
    if re.match(rf'^{re.escape(app_ws)}qs\s*=', L):
        qs_idx = k
        break
    k += 1

# si no hallamos 'qs =', probamos tras 'method ='
if qs_idx is None:
    k = app_hdr_idx + 1
    method_idx = None
    while k < end_idx:
        L = lines[k]
        if L.strip()=="":
            k += 1; continue
        ind = len(L) - len(L.lstrip(" "))
        if ind <= app_base: break
        if re.match(rf'^{re.escape(app_ws)}method\s*=', L):
            method_idx = k
            break
        k += 1
    insert_after = method_idx if method_idx is not None else app_hdr_idx
else:
    insert_after = qs_idx

# 4) no duplicar si ya existe handler OPTIONS
already = False
for L in lines[app_hdr_idx+1:min(end_idx, app_hdr_idx+80)]:
    if "OPTIONS" in L and "Access-Control-Allow-Methods" in "\n".join(lines[app_hdr_idx:app_hdr_idx+120]):
        already = True
        break

if not already:
    IND = app_ws + "    "
    block = [
        IND + "# Preflight CORS/OPTIONS para /api/*",
        IND + "if method == \"OPTIONS\" and path.startswith(\"/api/\"):",
        IND + "    origin = environ.get(\"HTTP_ORIGIN\")",
        IND + "    hdrs = [",
        IND + "        (\"Content-Type\", \"application/json; charset=utf-8\"),",
        IND + "        (\"Access-Control-Allow-Methods\", \"GET,POST,OPTIONS\"),",
        IND + "        (\"Access-Control-Allow-Headers\", \"Content-Type, Accept\"),",
        IND + "        (\"Access-Control-Max-Age\", \"600\"),",
        IND + "    ]",
        IND + "    if origin:",
        IND + "        hdrs += [",
        IND + "            (\"Access-Control-Allow-Origin\", origin),",
        IND + "            (\"Vary\", \"Origin\"),",
        IND + "            (\"Access-Control-Allow-Credentials\", \"true\"),",
        IND + "            (\"Access-Control-Expose-Headers\", \"Link, X-Next-Cursor, X-Summary-Applied, X-Summary-Limit\"),",
        IND + "        ]",
        IND + "    start_response(\"204 No Content\", hdrs)",
        IND + "    return [b\"\"]",
        ""
    ]
    lines[insert_after+1:insert_after+1] = block
    end_idx += len(block)
    print("• inyectado handler OPTIONS en _app")

# 5) asegurar 'return _app' al final de _middleware
has_return = any(re.match(rf'^{re.escape(mw_ws)}return\s+_app\s*$', L) for L in lines[mw_hdr_idx:end_idx])
if not has_return:
    lines.insert(end_idx, mw_ws + "return _app")
    end_idx += 1
    print("• añadido 'return _app' al final de _middleware")

out = "\n".join(lines)
if out == src:
    print("OK: no había nada para cambiar")
    if not gate(): sys.exit(1)
    sys.exit(0)

bak = W.with_suffix(".py.inline_cors_options_patch.bak")
if not bak.exists():
    shutil.copyfile(W, bak)
W.write_text(out, encoding="utf-8")
print(f"patched: OPTIONS inline + return(_app) | backup={bak.name}")

if not gate(): sys.exit(1)
