#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)

def R(): return W.read_text(encoding="utf-8")
def norm(s: str) -> str: return s.replace("\r\n","\n").replace("\r","\n").replace("\t","    ")

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

# Localiza def _app(environ, start_response): (puede estar anidada en _middleware)
m_app = re.search(r'(?m)^([ ]*)def[ ]+_app\s*\(\s*environ\s*,\s*start_response\s*\)\s*:\s*$', src)
if not m_app:
    print("✗ no encontré 'def _app(environ, start_response):'"); sys.exit(1)

app_ws = m_app.group(1); app_base = len(app_ws)
app_hdr_idx = src[:m_app.start()].count("\n")

# Encuentra el final del bloque _app por dedent
j = app_hdr_idx + 1
end_idx = len(lines)
while j < len(lines):
    L = lines[j]
    if L.strip() and (len(L) - len(L.lstrip(" "))) <= app_base:
        end_idx = j
        break
    j += 1

# Encuentra asignaciones de path/method/qs (preferimos insertar luego del último hallado)
assign_pat = re.compile(rf'^{re.escape(app_ws)}    (path|method|qs)\s*=')
last_assign_idx = None
for k in range(app_hdr_idx+1, end_idx):
    if assign_pat.match(lines[k] or ""):
        last_assign_idx = k

if last_assign_idx is None:
    # como mínimo exigimos 'method' y 'path' — si no existen, los insertamos al inicio del cuerpo
    inject = [
        app_ws + "    " + 'path   = environ.get("PATH_INFO", "") or ""',
        app_ws + "    " + 'method = (environ.get("REQUEST_METHOD", "GET") or "GET").upper()',
        app_ws + "    " + 'qs     = environ.get("QUERY_STRING", "") or ""',
        ""
    ]
    lines[app_hdr_idx+1:app_hdr_idx+1] = inject
    end_idx += len(inject)
    last_assign_idx = app_hdr_idx + 3  # índice de 'qs = ...'

# Busca bloque preflight existente (comentario o el if)
start_pre = None
# intentamos detectar comentario guía primero
for k in range(app_hdr_idx+1, end_idx):
    L = lines[k]
    if L.strip().startswith("# Preflight CORS/OPTIONS"):
        start_pre = k
        break
if start_pre is None:
    for k in range(app_hdr_idx+1, end_idx):
        L = lines[k]
        if re.match(rf'^{re.escape(app_ws)}    if\s+method\s*==\s*"OPTIONS"\s*and\s*path\.startswith\("/api/"\)\s*:\s*$', L):
            start_pre = k
            break

# Si no existe, lo insertamos; si existe pero está antes de las asignaciones, lo movemos
pre_block = None
if start_pre is not None:
    # delimitar fin del bloque preflight por dedent (<= app_base+4) o EOF
    k = start_pre + 1
    while k < end_idx:
        L = lines[k]
        if L.strip() and (len(L) - len(L.lstrip(" "))) <= app_base + 4:
            break
        k += 1
    pre_block = lines[start_pre:k]
    # Si está antes de las asignaciones, lo movemos
    if start_pre < last_assign_idx:
        del lines[start_pre:k]
        end_shift = k - start_pre
        end_idx -= end_shift
        insert_at = last_assign_idx + 1
        lines[insert_at:insert_at] = pre_block + [""]
        end_idx += len(pre_block) + 1
        print("• movido bloque preflight debajo de path/method/qs")
else:
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
    insert_at = last_assign_idx + 1
    lines[insert_at:insert_at] = pre_block
    end_idx += len(pre_block)
    print("• insertado bloque preflight tras path/method/qs")

# (Opcional) Garantiza que _middleware termina con "return _app" dentro de su indent correcto
src2 = "\n".join(lines)
m_mw = re.search(r'(?m)^([ ]*)def[ ]+_middleware\([^)]*\)\s*(?:->\s*[^:]+)?\s*:\s*$', src2)
if m_mw:
    mw_ws = m_mw.group(1); mw_base = len(mw_ws)
    mw_hdr_idx = src2[:m_mw.start()].count("\n")
    # fin de _middleware
    j = mw_hdr_idx + 1
    end_mw = len(lines)
    while j < len(lines):
        L = lines[j]
        if L.strip() and (len(L) - len(L.lstrip(" "))) <= mw_base:
            end_mw = j; break
        j += 1
    has_ret = False
    for k in range(mw_hdr_idx+1, end_mw):
        if lines[k].strip() == "return _app" and (len(lines[k]) - len(lines[k].lstrip(" "))) == mw_base + 4:
            has_ret = True; break
    if not has_ret:
        lines.insert(end_mw, mw_ws + "    return _app")
        print("• añadido 'return _app' al final de _middleware")

out = "\n".join(lines)
if out == src:
    print("OK: no había nada para cambiar")
    if not gate(): sys.exit(1)
    sys.exit(0)

bak = W.with_suffix(".py.fix_preflight_position.bak")
if not bak.exists():
    shutil.copyfile(W, bak)
W.write_text(out, encoding="utf-8")
print(f"patched: preflight reubicado/canonicalizado | backup={bak.name}")

if not gate(): sys.exit(1)
