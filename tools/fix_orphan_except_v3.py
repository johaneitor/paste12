#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ wsgiapp/__init__.py no existe"); sys.exit(2)

def norm(s:str)->str:
    s = s.replace("\r\n","\n").replace("\r","\n")
    if "\t" in s: s = s.replace("\t","    ")
    return s

s = norm(W.read_text(encoding="utf-8"))
lines = s.split("\n")
n = len(lines)
changed = False

def indw(l:str)->int: return len(l) - len(l.lstrip(" "))

def is_header(l:str)->bool:
    t = l.lstrip()
    return bool(re.match(r'^(def |class |if |elif |else:|for |while |with |try:|except\b|finally:|@)', t))

def is_block_end_for(indent:int, idx:int)->bool:
    # detecta si lines[idx] marca un “corte” de bloque para el indent dado
    if idx < 0: return True
    L = lines[idx]
    if L.strip()=="" or L.lstrip().startswith("#"):
        return False
    return indw(L) < indent

def has_prior_try_same_indent(i:int, base:int)->bool:
    # Busca hacia atrás un 'try:' al mismo indent, sin atravesar a un indent menor
    j = i-1
    while j >= 0:
        L = lines[j]
        if L.strip()=="" or L.lstrip().startswith("#"):
            j -= 1; continue
        iw = indw(L)
        if iw < base:           # se salió del bloque
            return False
        if iw == base and re.match(r'^\s*try:\s*$', L):
            return True
        j -= 1
    return False

hdr_re = re.compile(r'^(except\b.*:|finally:)\s*$')

i = 0
while i < n:
    L = lines[i]
    m = hdr_re.match(L.lstrip())
    if m:
        base = indw(L)
        # ¿hay try: antes al mismo indent dentro del mismo bloque?
        if not has_prior_try_same_indent(i, base):
            # Inserta try/pass antes del except/finally
            lines.insert(i, (" " * base) + "try:")
            lines.insert(i+1, (" " * (base+4)) + "pass")
            n += 2
            changed = True
            i += 2
            continue
    i += 1

out = "\n".join(lines)
if changed:
    bak = W.with_suffix(".py.fix_orphan_except_v3.bak")
    if not bak.exists(): shutil.copyfile(W, bak)
    W.write_text(out, encoding="utf-8")
    print(f"patched: except/finally huérfanos cubiertos con try/pass | backup={bak.name}")
else:
    print("OK: no except/finally huérfanos detectados")

# Gate de compilación + ventana de contexto si falla
try:
    py_compile.compile(str(W), doraise=True)
    print("✓ py_compile OK")
except Exception as e:
    print("✗ py_compile falla:", e)
    tb = traceback.format_exc()
    m = re.search(r'__init__\.py, line (\d+)', tb)
    if m:
        ln = int(m.group(1))
        ctx = out.splitlines()
        a = max(1, ln-30); b = min(len(ctx), ln+30)
        print(f"\n--- Ventana {a}-{b} ---")
        for k in range(a, b+1):
            print(f"{k:5d}: {ctx[k-1]}")
    sys.exit(1)
