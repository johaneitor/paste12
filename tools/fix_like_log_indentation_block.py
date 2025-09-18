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

def indw(line:str)->int:
    return len(line) - len(line.lstrip(" "))

def find_next_nonempty(i:int)->int:
    j = i+1
    while j < n and lines[j].strip() == "":
        j += 1
    return j

def end_of_ddl_block(start:int)->int:
    """
    start apunta a la línea 'cx.execute(_text("""'.
    Devuelve el índice de la PRIMER línea *después* del bloque DDL + ')))'.
    """
    opened = False
    i = start
    while i < n:
        L = lines[i]
        # toggle en """ o '''
        for _m in re.finditer(r'(?<!\\)(\"\"\"|\'\'\')', L):
            opened = not opened
        # cuando salimos de triple comillas, buscamos línea con ')))'
        if not opened:
            if re.search(r'\)\)\)\s*$', L):
                return i+1
            # a veces el ')))' viene en la línea siguiente
            if i+1 < n and re.search(r'^\s*\)\)\)\s*$', lines[i+1]):
                return i+2
        i += 1
    return start+1

i = 0
while i < n:
    L = lines[i]
    # match a 'try:' puro
    if re.match(r'^\s*try:\s*$', L):
        base_w = indw(L)
        base_ws = " " * base_w
        j = find_next_nonempty(i)
        if j < n:
            nxt = lines[j]
            # si el next no está indentado más que el try, está mal
            if indw(nxt) <= base_w and re.search(r'cx\.execute\(_text\(\"\"\"', nxt):
                # indentar el bloque DDL completo
                start = j
                end = end_of_ddl_block(start)
                for k in range(start, min(end, n)):
                    lines[k] = base_ws + "    " + lines[k].lstrip(" ")
                changed = True
                i = end
                continue
    i += 1

out = "\n".join(lines)
if changed:
    bak = W.with_suffix(".py.fix_like_log_indent.bak")
    if not bak.exists():
        shutil.copyfile(W, bak)
    W.write_text(out, encoding="utf-8")
    print(f"patched: DDL bajo try indentado correctamente | backup={bak.name}")
else:
    print("OK: no se detectaron 'try:' seguidos de DDL mal indentado")

# Gate de compilación + ventana útil si falla
try:
    py_compile.compile(str(W), doraise=True)
    print("✓ py_compile OK")
except Exception as e:
    print("✗ py_compile falla:", e)
    tb = traceback.format_exc()
    m = re.search(r'__init__\.py, line (\d+)', tb)
    if m:
        ln = int(m.group(1))
        txt = W.read_text(encoding="utf-8").splitlines()
        start = max(1, ln-30); end = min(len(txt), ln+30)
        print(f"\n--- Ventana {start}-{end} ---")
        for k in range(start, end+1):
            print(f"{k:5d}: {txt[k-1]}")
    sys.exit(1)
