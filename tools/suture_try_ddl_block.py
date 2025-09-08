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

def in_triple_scan(start_i:int)->int:
    """Dado el índice de línea donde aparece _text(\"\"\", devuelve el índice
    (incluido) donde termina el bloque con la línea que cierra las triple comillas
    y los '))' de execute. Si no puede, retorna start_i."""
    i = start_i
    opened = False
    while i < n:
        L = lines[i]
        # toggles en """ o ''' no escapados
        for m in re.finditer(r'(?<!\\)(\"\"\"|\'\'\')', L):
            opened = not opened
        if not opened:
            # buscamos si en esta o en la siguiente línea cierran los '))'
            # (heurística tolerante)
            if re.search(r'\)\)\)\s*$', L) or (i+1 < n and re.search(r'^\s*\)\)\)\s*$', lines[i+1])):
                return i+1 if re.search(r'\)\)\)\s*$', L) else i+2
            # si no vemos ))) igual consideramos que cierra aquí
            return i+1
        i += 1
    return start_i+1

# 1) encontrar todos los cx.execute(_text(""" ... """)) y suturar try/except
i = 0
while i < n:
    L = lines[i]
    if 'cx.execute(_text("""' in L:
        base_w = indw(L)
        base_ws = " " * base_w

        # buscar si ya hay un 'try:' al mismo indent en las líneas anteriores inmediatas
        k = i - 1
        has_try = False
        # retrocede sobre líneas vacías o comentarios
        while k >= 0 and (lines[k].strip() == "" or lines[k].lstrip().startswith("#")):
            k -= 1
        if k >= 0 and indw(lines[k]) == base_w and re.match(r'^\s*try:\s*$', lines[k]):
            has_try = True

        # si no hay try:, buscamos si hay un 'with _engine().begin() as cx:' al mismo nivel para poner try: justo encima
        insert_try_at = None
        if not has_try:
            # intenta encontrar 'with _engine...' inmediatamente arriba
            kk = i - 1
            while kk >= 0 and lines[kk].strip() == "":
                kk -= 1
            if kk >= 0 and indw(lines[kk]) == base_w and 'with _engine().begin() as cx' in lines[kk]:
                insert_try_at = kk
            else:
                insert_try_at = i

        # localizar fin del bloque DDL
        end = in_triple_scan(i)

        # comprobar si ya existe un except/finally a mismo nivel tras el bloque
        j = end
        has_handler = False
        while j < n and lines[j].strip() == "":
            j += 1
        if j < n and indw(lines[j]) == base_w and re.match(r'^(except\b|finally\b)', lines[j].lstrip()):
            has_handler = True

        # aplicar suturas
        delta = 0
        if not has_try and insert_try_at is not None:
            lines.insert(insert_try_at, base_ws + "try:")
            n += 1
            changed = True
            # si insertamos antes de i, el índice del execute se corre
            if insert_try_at <= i:
                i += 1
                end += 1
                if j >= insert_try_at:
                    j += 1
            delta += 1

        if not has_handler:
            lines.insert(end, base_ws + "except Exception:")
            lines.insert(end+1, base_ws + "    pass")
            n += 2
            changed = True
            # ajusta i para saltar después de lo insertado
            i = end + 2
            continue

    i += 1

out = "\n".join(lines)
if changed:
    bak = W.with_suffix(".py.suture_try_ddl.bak")
    if not bak.exists():
        shutil.copyfile(W, bak)
    W.write_text(out, encoding="utf-8")
    print(f"patched: sutured DDL try/except | backup={bak.name}")
else:
    print("OK: no DDL blocks por suturar")

# Gate de compilación con ventana útil si falla
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
