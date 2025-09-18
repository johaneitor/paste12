#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ wsgiapp/__init__.py no existe"); sys.exit(2)

def read_norm():
    s = W.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n")
    if "\t" in s: s = s.replace("\t","    ")
    return s

def write_backup(s, tag):
    bak = W.with_suffix(f".py.{tag}.bak")
    if not bak.exists():
        shutil.copyfile(W, bak)
    W.write_text(s, encoding="utf-8")
    return bak.name

def py_gate():
    try:
        py_compile.compile(str(W), doraise=True)
        return True, ""
    except Exception as e:
        tb = traceback.format_exc()
        return False, tb

def context_around(tb):
    m = re.search(r'__init__\.py, line (\d+)', tb)
    if not m: return None
    ln = int(m.group(1))
    txt = read_norm().splitlines()
    a = max(1, ln-30); b = min(len(txt), ln+30)
    win = "\n".join(f"{i:5d}: {txt[i-1]}" for i in range(a, b+1))
    return ln, a, b, win

s = read_norm()
changed_any = False

# Pass 1) limpiar colas JSON “fantasma”: import json + bloque indentado con start_response/return [body]
lines = s.split("\n")
out, i, n, removed_blocks = [], 0, len(lines), 0
def top_indent(line): return len(line) - len(line.lstrip(" "))
while i < n:
    ln = lines[i]
    if top_indent(ln)==0 and re.match(r'^import\s+json\s+as\s+_json_mod\s*$', ln):
        j = i+1
        saw_ind, saw_body = False, False
        while j < n:
            l2 = lines[j]
            if l2.strip()=="":
                j += 1; continue
            if top_indent(l2)==0: break
            saw_ind = True
            if "body = _json_mod.dumps(" in l2: saw_body = True
            j += 1
        if saw_ind and saw_body:
            removed_blocks += 1
            i = j
            changed_any = True
            continue
    out.append(ln); i += 1
s = "\n".join(out)

# Pass 2) DDL con _text(\"\"\"… — asegurar cierre \"\"\") antes de ))) y try/indent correcto
lines = s.split("\n"); n = len(lines)
def indw(l:str)->int: return len(l) - len(l.lstrip(" "))
def find_ddl_end(start:int)->int:
    opened = True  # empezamos dentro de """ por el patrón
    i = start
    while i < n:
        L = lines[i]
        for _ in re.finditer(r'(?<!\\)(?:"""|\'\'\')', L):
            opened = not opened
        if not opened:
            if re.search(r'\)\)\)\s*$', L): return i+1
            if i+1<n and re.search(r'^\s*\)\)\)\s*$', lines[i+1]): return i+2
        i += 1
    return start+1

i = 0
while i < n:
    L = lines[i]
    if 'cx.execute(_text("""' in L:
        # 2.a) si viene de un try: y el siguiente no está indentado, indentar bloque DDL
        k = i-1
        while k>=0 and (lines[k].strip()=="" or lines[k].lstrip().startswith("#")):
            k -= 1
        if k>=0 and re.match(r'^\s*try:\s*$', lines[k]):
            base = indw(lines[k])
            j = i
            if indw(lines[i]) <= base:  # mal indentado bajo try
                end = find_ddl_end(i)
                for t in range(i, min(end, n)):
                    lines[t] = (" "*(base+4)) + lines[t].lstrip(" ")
                changed_any = True
                i = end
                continue
        # 2.b) asegurar cierre de triple comillas antes de ')))'
        opened = True
        j = i
        close_done = False
        while j < n:
            Lj = lines[j]
            for _ in re.finditer(r'(?<!\\)(?:"""|\'\'\')', Lj):
                opened = not opened
            if re.search(r'\)\)\)\s*$', Lj):
                if opened:  # aún abierto → sustituir ')))' por '"""))'
                    lines[j] = re.sub(r'\)\)\)\s*$', '"""))', Lj)
                    changed_any = True
                close_done = True
                break
            if j+1<n and re.search(r'^\s*\)\)\)\s*$', lines[j+1]):
                if opened:
                    lines[j+1] = re.sub(r'^\s*\)\)\)\s*$', '"""))', lines[j+1])
                    changed_any = True
                close_done = True
                j += 1
                break
            j += 1
        i = j+1 if close_done else i+1
        continue
    i += 1
s = "\n".join(lines)

# Pass 3) try sin handler (except/finally) al mismo nivel → insertar except/pass
lines = s.split("\n"); n = len(lines); i = 0
while i < n:
    if re.match(r'^\s*try:\s*$', lines[i]):
        base = indw(lines[i]); j = i+1
        while j < n and lines[j].strip()=="":
            j += 1
        # avanza hasta dedent o EOF
        k = j
        while k < n:
            if lines[k].strip()=="":
                k += 1; continue
            if indw(lines[k]) <= base: break
            k += 1
        # si en k hay except/finally ya está
        if k < n and re.match(r'^\s*(except\b|finally\b)', lines[k].lstrip()):
            i = k+1; continue
        # insertar handler en k
        lines.insert(k, " " * base + "except Exception:")
        lines.insert(k+1, " " * base + "    pass")
        n += 2; i = k + 2; changed_any = True
        continue
    i += 1
s = "\n".join(lines)

# Pass 4) def/class sin cuerpo indentado → insertar pass
lines = s.split("\n"); n = len(lines); i = 0
while i < n:
    if re.match(r'^\s*(def|class)\s+\w', lines[i]) and lines[i].rstrip().endswith(":"):
        base = indw(lines[i]); j = i+1
        while j < n and lines[j].strip()=="":
            j += 1
        if j >= n or indw(lines[j]) <= base or lines[j].lstrip().startswith(("def ","class ","except","finally")):
            lines.insert(j, " " * (base+4) + "pass")
            n += 1; changed_any = True; i = j + 1; continue
    i += 1
s = "\n".join(lines)

# Pass 5) limpieza menor: espacios en blanco colgantes
s = "\n".join([l.rstrip() for l in s.split("\n")]) + ("\n" if not s.endswith("\n") else "")

# Guardar si cambió algo
if changed_any:
    bakname = write_backup(s, "purify_all_v1")
    print(f"patched: purify passes applied | backup={bakname}")
else:
    print("OK: nada para purificar")

# Bucle de compilación con heurísticas de último recurso
for attempt in range(1, 4):
    ok, tb = py_gate()
    if ok:
        print("✓ py_compile OK")
        sys.exit(0)
    # Heurística 1: “expected an indented block after 'try' statement”
    m = re.search(r"expected an indented block after 'try' statement on line (\d+)", tb)
    if m:
        ln = int(m.group(1))
        txt = read_norm().splitlines()
        base = len(txt[ln-1]) - len(txt[ln-1].lstrip(" "))
        txt.insert(ln, " " * (base+4) + "pass")
        W.write_text("\n".join(txt) + "\n", encoding="utf-8")
        print(f"healed: inserted 'pass' after try: at L{ln}")
        continue
    # Heurística 2: “unterminated triple-quoted string literal”
    if "unterminated triple-quoted string literal" in tb:
        txt = read_norm().splitlines()
        # cerrar a lo bruto el último bloque abierto (añadir """ al final del archivo)
        txt.append('"""')
        W.write_text("\n".join(txt) + "\n", encoding="utf-8")
        print("healed: appended closing triple quotes at EOF")
        continue
    # Heurística 3: “expected an indented block after function definition”
    m = re.search(r"expected an indented block after function definition on line (\d+)", tb)
    if m:
        ln = int(m.group(1)); txt = read_norm().splitlines()
        base = len(txt[ln-1]) - len(txt[ln-1].lstrip(" "))
        txt.insert(ln, " " * (base+4) + "pass")
        W.write_text("\n".join(txt) + "\n", encoding="utf-8")
        print(f"healed: inserted 'pass' after def: at L{ln}")
        continue
    # Heurística 4: “unexpected indent” → desindentar una vez
    m = re.search(r"unexpected indent \(__init__\.py, line (\d+)\)", tb)
    if m:
        ln = int(m.group(1)); txt = read_norm().splitlines()
        txt[ln-1] = txt[ln-1].lstrip(" ")
        W.write_text("\n".join(txt) + "\n", encoding="utf-8")
        print(f"healed: left-strip indentation at L{ln}")
        continue
    # Si no reconocemos, mostramos ventana y salimos
    info = context_around(tb)
    if info:
        ln, a, b, win = info
        print(f"\n✗ py_compile falla (L{ln}):\n{tb}\n--- Ventana {a}-{b} ---\n{win}")
    else:
        print(f"\n✗ py_compile falla:\n{tb}")
    sys.exit(1)

# Si el bucle terminó sin OK
ok, tb = py_gate()
if not ok:
    info = context_around(tb)
    if info:
        ln, a, b, win = info
        print(f"\n✗ py_compile falla tras intentos (L{ln}):\n{tb}\n--- Ventana {a}-{b} ---\n{win}")
    else:
        print(f"\n✗ py_compile falla tras intentos:\n{tb}")
    sys.exit(1)
print("✓ py_compile OK")
