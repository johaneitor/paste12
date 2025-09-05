#!/usr/bin/env python3
import pathlib, re, sys, py_compile, shutil

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("ERROR: wsgiapp/__init__.py no existe"); sys.exit(2)

raw = W.read_text(encoding="utf-8")
s = raw.replace("\r\n","\n").replace("\r","\n").replace("\t","    ")

# localiza la línea de def _middleware(...)
pat = re.compile(r'(?m)^([ ]*)def\s+_middleware\s*\(\s*inner_app\s*:\s*.*?\)\s*->\s*Callable\s*:\s*$')
m = pat.search(s)
if not m:
    print("AVISO: no encontré def _middleware(...). No cambio nada.")
    try:
        py_compile.compile(str(W), doraise=True); print("✓ py_compile OK (sin cambios)")
    except Exception as e:
        print("✗ py_compile falla:", e); sys.exit(1)
    sys.exit(0)

indent = m.group(1)
lines = s.split("\n")
start_idx = s[:m.start()].count("\n")  # índice de la línea con 'def _middleware'

# Determinar si YA tiene cuerpo: la siguiente línea no vacía debe tener indent > base
i = start_idx + 1
has_body = False
while i < len(lines):
    ln = lines[i]
    if ln.strip() == "":
        i += 1; continue
    cur_indent = len(ln) - len(ln.lstrip(" "))
    if cur_indent > len(indent):
        has_body = True
    break

if has_body:
    # Nada que hacer
    try:
        py_compile.compile(str(W), doraise=True); print("✓ _middleware ya tenía cuerpo; py_compile OK")
    except Exception as e:
        print("✗ py_compile falla:", e); sys.exit(1)
    sys.exit(0)

# Insertar cuerpo seguro (passthrough). No depende de helpers externos.
body = f"""{indent}    def app(environ, start_response):
{indent}        if inner_app is not None:
{indent}            return inner_app(environ, start_response)
{indent}        start_response("404 NOT FOUND",[("Content-Type","text/plain; charset=utf-8"),("Content-Length","0")])
{indent}        return [b""]
{indent}    return app
"""

# Insertamos el cuerpo inmediatamente después de la línea def
lines.insert(start_idx+1, body.rstrip("\n"))
out = "\n".join(lines)

# Backup + escribir + gate
bak = W.with_suffix(".py.fix_middleware.bak")
if not bak.exists(): shutil.copyfile(W, bak)
W.write_text(out, encoding="utf-8")

try:
    py_compile.compile(str(W), doraise=True)
    print("✓ _middleware reparado y py_compile OK")
    print("Backup en:", bak)
except Exception as e:
    print("✗ py_compile falla tras el fix:", e)
    print("Backup en:", bak)
    sys.exit(1)
