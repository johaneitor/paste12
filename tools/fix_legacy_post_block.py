#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)

def R(): return W.read_text(encoding="utf-8", errors="ignore")
def WRT(s): W.write_text(s, encoding="utf-8")

src = R().replace("\r\n","\n").replace("\r","\n").replace("\t","    ")
lines = src.split("\n")

# Localiza 'if path == "/api/notes" and method == "POST":'
m = re.search(r'(?m)^([ ]*)if\s+path\s*==\s*"/api/notes"\s*and\s*method\s*==\s*"POST"\s*:\s*$', src)
if not m:
    print("✗ no encontré el header de POST /api/notes"); sys.exit(1)
if_ws = m.group(1)
if_base = len(if_ws)
if_hdr_idx = src[:m.start()].count("\n")

# Busca el 'return _finish(...)' dentro del bloque POST
ret_idx = None
for i in range(if_hdr_idx+1, min(if_hdr_idx+200, len(lines))):
    L = lines[i]
    if not L.strip(): continue
    ind = len(L) - len(L.lstrip(" "))
    if ind <= if_base:  # dedent => fin del bloque
        break
    if "return _finish(" in L:
        ret_idx = i
        break

if ret_idx is None:
    print("✗ no encontré 'return _finish' dentro de POST /api/notes"); sys.exit(1)

# Encuentra el siguiente bloque de rutas: if path.startswith("/api/notes/") ...
next_block_idx = None
pat_next = re.compile(r'^' + re.escape(if_ws) + r'if\s+path\.startswith\("/api/notes/"\)\s*and\s*method\s*==\s*"POST"\s*:\s*$')
for i in range(ret_idx+1, min(if_hdr_idx+400, len(lines))):
    L = lines[i]
    if pat_next.match(L or ""):
        next_block_idx = i
        break
# Si no lo hallamos, cae al próximo dedent al nivel del 'if' actual
if next_block_idx is None:
    for i in range(ret_idx+1, len(lines)):
        L = lines[i]
        ind = len(L) - len(L.lstrip(" "))
        if L.strip() and ind <= if_base:
            next_block_idx = i
            break

if next_block_idx is None:
    print("✗ no pude delimitar el siguiente bloque; no hago cambios")
    sys.exit(1)

# Si hay líneas entre el return y el siguiente bloque, y arrancan con 'ctype =' u otras del parser legado, las borramos
start_cut = ret_idx + 1
end_cut   = next_block_idx
has_legacy = False
for i in range(start_cut, end_cut):
    if lines[i].lstrip().startswith(("ctype = ", "length =", "raw = ", "data = {}", "if \"application/json\" in ctype", "from urllib.parse import parse_qs")):
        has_legacy = True
        break

if not has_legacy:
    print("OK: no vi bloque legado post-return (nada que cortar)")
else:
    bak = W.with_suffix(".py.strip_legacy_post.bak")
    if not bak.exists():
        shutil.copyfile(W, bak)
    del lines[start_cut:end_cut]
    WRT("\n".join(lines))
    print(f"patched: removido bloque POST legado tras return | backup={bak.name}")

# Gate de compilación con ventana si falla
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
