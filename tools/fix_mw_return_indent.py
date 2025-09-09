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

# Localiza el header de _middleware (con o sin "-> retorno")
m_hdr = re.search(r'(?m)^([ ]*)def[ ]+_middleware\([^)]*\)\s*(?:->\s*[^:]+)?\s*:\s*$', src)
if not m_hdr:
    print("✗ no encontré 'def _middleware(...)'"); sys.exit(1)

base_ws = m_hdr.group(1)
base = len(base_ws)
hdr_idx = src[:m_hdr.start()].count("\n")

# Quita un "pass" inmediato si existe (ruido previo)
i = hdr_idx + 1
while i < len(lines) and lines[i].strip() == "":
    i += 1
if i < len(lines) and lines[i].strip() == "pass":
    del lines[i]

# Recalcula límites tras posible borrado
src2 = "\n".join(lines)
m_hdr = re.search(r'(?m)^([ ]*)def[ ]+_middleware\([^)]*\)\s*(?:->\s*[^:]+)?\s*:\s*$', src2)
base_ws = m_hdr.group(1); base = len(base_ws)
hdr_idx = src2[:m_hdr.start()].count("\n")

# Encuentra fin del bloque por dedent (primera línea con indent <= base y no vacía)
j = hdr_idx + 1
end_idx = len(lines)
while j < len(lines):
    L = lines[j]
    if L.strip() and (len(L) - len(L.lstrip(" "))) <= base:
        end_idx = j
        break
    j += 1

# Normaliza "return _app":
#  a) si hay un "return _app" fuera (indent <= base) justo en el límite, bórralo
if end_idx < len(lines):
    L = lines[end_idx]
    if L.strip() == "return _app" and (len(L) - len(L.lstrip(" "))) <= base:
        del lines[end_idx]
        # no mover end_idx; apunta al mismo lugar

#  b) si NO hay un "return _app" válido dentro, insértalo con indent base+4 justo antes de end_idx
has_valid = False
for k in range(hdr_idx+1, min(end_idx, len(lines))):
    L = lines[k]
    if L.strip() == "return _app" and (len(L) - len(L.lstrip(" "))) == base + 4:
        has_valid = True
        break
if not has_valid:
    insert_pos = end_idx  # antes del dedent
    lines.insert(insert_pos, base_ws + "    " + "return _app")
    print("• insertado 'return _app' dentro de _middleware")

out = "\n".join(lines)
if out == src:
    print("OK: no había nada para cambiar")
    if not gate(): sys.exit(1)
    sys.exit(0)

bak = W.with_suffix(".py.fix_mw_return_indent.bak")
if not bak.exists():
    shutil.copyfile(W, bak)
W.write_text(out, encoding="utf-8")
print(f"patched: 'return _app' reindentado | backup={bak.name}")

if not gate(): sys.exit(1)
