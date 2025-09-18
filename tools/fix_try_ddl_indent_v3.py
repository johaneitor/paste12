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
def next_nonempty(i:int)->int:
    j=i+1
    while j < n and lines[j].strip()=="":
        j+=1
    return j

def ddl_block_end(start:int)->int:
    """
    start apunta a la PRIMER línea del cuerpo a reindentar.
    Detecta bloques DDL estilo: cx.execute(_text(\"\"\" ... \"\"\")) )
    y devuelve el índice de la PRIMERA línea DESPUÉS del bloque.
    """
    i = start
    opened = False
    saw_triple = False
    while i < n:
        L = lines[i]
        # toggle en """ o ''' no escapadas
        for m in re.finditer(r'(?<!\\)(\"\"\"|\'\'\')', L):
            opened = not opened
            saw_triple = True
        if saw_triple:
            # cerró triple y vemos si ya cerraron los ')))'
            if not opened:
                # ')))' puede estar en la misma o siguiente línea
                if re.search(r'\)\)\)\s*$', L): return i+1
                if i+1 < n and re.search(r'^\s*\)\)\)\s*$', lines[i+1]): return i+2
        else:
            # variante sin triple-comilla: cerrar con '))'
            if re.search(r'\)\)\s*$', L): return i+1
            if i+1 < n and re.search(r'^\s*\)\)\s*$', lines[i+1]): return i+2
        i += 1
    # fallback: corta en la siguiente línea significativa
    j = next_nonempty(start)
    return j if j>start else start+1

i = 0
while i < n:
    L = lines[i]
    # localizar encabezado try:
    if re.match(r'^\s*try:\s*$', L):
        base = indw(L)
        body_i = next_nonempty(i)
        if body_i >= n:
            i += 1
            continue
        body_line = lines[body_i]
        # Si el "cuerpo" no está más indentado que el try → reindentar
        if indw(body_line) <= base:
            # solo reindentamos si parece ser un DDL/execute para no tocar otras cosas
            looks_ddl = ('cx.execute(_text(' in body_line) or ('CREATE ' in body_line.upper())
            if looks_ddl:
                end = ddl_block_end(body_i)
                # aplica +4 espacios a todo el bloque cuerpo
                for k in range(body_i, min(end, n)):
                    if indw(lines[k]) <= base:  # no doble-indent si ya estaba bien
                        lines[k] = (" "*(base+4)) + lines[k].lstrip(" ")
                changed = True
                i = end
                continue
    i += 1

out = "\n".join(lines)
if changed:
    bak = W.with_suffix(".py.fix_try_ddl_indent_v3.bak")
    if not bak.exists(): shutil.copyfile(W, bak)
    W.write_text(out, encoding="utf-8")
    print(f"patched: DDL bajo try reindentado | backup={bak.name}")
else:
    print("OK: nada que reindentar")

# Gate de compilación + ventana útil
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
