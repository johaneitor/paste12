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

# localiza todas las ocurrencias del INSERT
targets = [i for i,l in enumerate(lines) if "INSERT INTO like_log" in l]
if not targets:
    print("OK: no se encontró 'INSERT INTO like_log' (nada que tocar)")
else:
    for t in targets:
        # busca el inicio del bloque de ejecución (cx.execute...) hacia arriba
        start = t
        while start > 0 and "cx.execute" not in lines[start]:
            start -= 1
        # si no hay cx.execute en esa zona, igual usamos la línea t como inicio
        if "cx.execute" not in lines[start]:
            start = t
        base = indw(lines[start])

        # ¿hay un 'try:' inmediatamente por encima con el mismo indent?
        try_line = None
        k = start - 1
        while k >= 0 and lines[k].strip() == "":
            k -= 1
        if k >= 0 and indw(lines[k]) == base and re.match(r'^\s*try:\s*$', lines[k]):
            try_line = k

        # delimita el final del “cuerpo” que debe quedar DENTRO del try:
        # nos quedamos hasta la primera línea con indent <= base (o EOF)
        end = start + 1
        while end < n:
            if lines[end].strip() == "":
                end += 1
                continue
            if indw(lines[end]) <= base:
                break
            end += 1

        # localiza 'inserted = True' cercano y lo asimila al cuerpo del try
        it_true = None
        for j in range(start, min(n, start+30)):
            if re.search(r'\binserted\s*=\s*True\b', lines[j]):
                it_true = j
                if j >= end:  # ampliar el cuerpo si estaba fuera
                    end = j + 1
                break

        # asegura que exista try: y except:
        if try_line is None:
            # insertar try: justo antes de 'start'
            lines.insert(start, " " * base + "try:")
            n += 1
            changed = True
            start += 1
            if end >= start:
                end += 1

        # reindentarlo todo (start..end-1) para que quede bajo el try (base+4)
        body_indent = base + 4
        for i in range(start, end):
            lines[i] = " " * body_indent + lines[i].lstrip(" ")

        # después del cuerpo, debe venir un except Exception: inserted=False
        ins_at = end
        # si lo que sigue ya es un except/finally correcto, no toques
        if ins_at < n and re.match(r'^\s*(except\b.*:|finally:)\s*$', lines[ins_at].lstrip()) and indw(lines[ins_at]) == base:
            pass
        else:
            lines.insert(ins_at, " " * base + "except Exception:")
            lines.insert(ins_at + 1, " " * (base + 4) + "inserted = False")
            n += 2
            changed = True

    out = "\n".join(lines)
    if changed:
        bak = W.with_suffix(".py.fix_like_insert_try_block.bak")
        if not bak.exists():
            shutil.copyfile(W, bak)
        W.write_text(out, encoding="utf-8")
        print(f"patched: bloque INSERT like_log normalizado | backup={bak.name}")
    else:
        print("OK: no cambió nada (ya estaba bien)")

# Gate de compilación con ventana si falla
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
        a = max(1, ln-30); b = min(len(txt), ln+30)
        print(f"\n--- Ventana {a}-{b} ---")
        for k in range(a, b+1):
            print(f"{k:5d}: {txt[k-1]}")
    sys.exit(1)
