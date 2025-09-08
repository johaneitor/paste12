#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ wsgiapp/__init__.py no existe"); sys.exit(2)

def norm(s: str) -> str:
    s = s.replace("\r\n","\n").replace("\r","\n")
    if "\t" in s: s = s.replace("\t","    ")
    return s

s = norm(W.read_text(encoding="utf-8"))
lines = s.split("\n")
n = len(lines)
changed = False

def indw(l: str) -> int:
    return len(l) - len(l.lstrip(" "))

def next_nonempty(i: int) -> int:
    j = i + 1
    while j < n and lines[j].strip() == "":
        j += 1
    return j

def find_update_block_start(i: int) -> int | None:
    # Busca el "cx.execute(_text(" inmediatamente posterior al if inserted:
    j = next_nonempty(i)
    # Si esa línea no está indentada más que el if, hay problema.
    # Aun así, permitimos localizar el cx.execute aunque esté al mismo nivel.
    for k in range(j, min(n, j+20)):
        if "cx.execute" in lines[k] and "_text(" in lines[k] and "UPDATE note SET likes" in "".join(lines[k:k+5]):
            return k
    return None

def find_paren_triple_close(start: int) -> int:
    """
    Dado el inicio (línea con cx.execute(_text(), avanza hasta cerrar el bloque de SQL y su '))' o ')'.
    Devuelve el índice de la PRIMER línea *después* del bloque.
    """
    opened_triple = False
    i = start
    while i < n:
        L = lines[i]
        for _m in re.finditer(r'(?<!\\)(\"\"\"|\'\'\')', L):
            opened_triple = not opened_triple
        if not opened_triple:
            # cierres típicos: ")))" o ")" en la siguiente línea al cerrar execute
            if re.search(r'\)\)\)\s*$', L):
                return i + 1
            if i + 1 < n and re.search(r'^\s*\)\)\)\s*$', lines[i+1]):
                return i + 2
        i += 1
    return start + 1

for i, L in enumerate(lines):
    if re.match(r'^\s*if\s+inserted\s*:\s*$', L):
        base = indw(L)
        body_i = next_nonempty(i)
        # ¿ya hay cuerpo indentado?
        if body_i < n and indw(lines[body_i]) > base:
            continue  # este if ya tiene cuerpo válido

        # Buscamos bloque UPDATE a meter dentro del if
        up_start = find_update_block_start(i)
        if up_start is None:
            # sin UPDATE cerca → al menos coloca 'pass'
            lines.insert(i+1, " "*(base+4) + "pass")
            n += 1
            changed = True
            continue

        up_end = find_paren_triple_close(up_start)
        if up_end <= up_start:
            # fallback por seguridad
            lines.insert(i+1, " "*(base+4) + "pass")
            n += 1
            changed = True
            continue

        # Reindentamos [up_start, up_end) para que queden bajo el if (base+4)
        want = base + 4
        for k in range(up_start, up_end):
            lines[k] = " " * want + lines[k].lstrip(" ")

        changed = True

out = "\n".join(lines)
if changed:
    bak = W.with_suffix(".py.fix_if_inserted_body.bak")
    if not bak.exists():
        shutil.copyfile(W, bak)
    W.write_text(out, encoding="utf-8")
    print(f"patched: cuerpo de 'if inserted:' normalizado | backup={bak.name}")
else:
    print("OK: no hacía falta ajustar 'if inserted:'")

# Gate de compilación + ventana si falla
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
        a = max(1, ln-40); b = min(len(txt), ln+40)
        print(f"\n--- Ventana {a}-{b} ---")
        for k in range(a, b+1):
            print(f"{k:5d}: {txt[k-1]}")
    sys.exit(1)
