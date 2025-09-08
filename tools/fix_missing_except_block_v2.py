#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ wsgiapp/__init__.py no existe"); sys.exit(2)

raw = W.read_text(encoding="utf-8")
s = raw.replace("\r\n","\n").replace("\r","\n")
if "\t" in s: s = s.replace("\t","    ")

lines = s.split("\n")
n = len(lines)
changed = False

# detecta si estamos dentro de triple-comillas
def mark_triple_zones(text_lines):
    zones = [False]*(len(text_lines))
    in_triple = False
    quote = None
    pat = re.compile(r'(?<!\\)(?P<q>"""|\'\'\')')
    for i, ln in enumerate(text_lines):
        for m in pat.finditer(ln):
            q = m.group('q')
            if not in_triple:
                in_triple = True; quote = q
            else:
                if q == quote:
                    in_triple = False; quote = None
        zones[i] = in_triple
    return zones

zones = mark_triple_zones(lines)

def indent_width(ln: str) -> int:
    return len(ln) - len(ln.lstrip(" "))

i = 0
while i < len(lines):
    ln = lines[i]
    if zones[i]:
        i += 1
        continue
    m = re.match(r'^([ ]*)try:\s*$', ln)
    if not m:
        i += 1
        continue

    base = m.group(1)
    base_w = len(base)

    # saltar líneas en blanco para encontrar comienzo de cuerpo
    j = i + 1
    while j < len(lines) and lines[j].strip() == "":
        j += 1

    # avanzar dentro del cuerpo hasta dedentar a nivel <= base
    k = j
    has_except_or_finally = False
    while k < len(lines):
        if zones[k]:
            k += 1
            continue
        cur = lines[k]
        cur_w = indent_width(cur)
        # si aparece except/finally en el mismo nivel que try → bloque correcto
        if cur_w == base_w and re.match(r'^(except\b|finally\b)', cur.lstrip()):
            has_except_or_finally = True
            break
        # si dedenta a nivel <= base y NO es except/finally → bloque termina sin except
        if cur.strip() != "" and cur_w <= base_w:
            break
        k += 1

    if not has_except_or_finally:
        # insertar 'except Exception: pass' ANTES de la dedent (en k)
        ins_idx = k
        lines.insert(ins_idx, base + "except Exception:")
        lines.insert(ins_idx + 1, base + "    pass")
        changed = True
        # actualizar zonas y avanzar después del bloque insertado
        zones = mark_triple_zones(lines)
        i = ins_idx + 2
    else:
        # el bloque ya posee except/finally
        i = k + 1

out = "\n".join(lines)
if changed:
    bak = W.with_suffix(".py.fix_missing_except_v2.bak")
    if not bak.exists():
        shutil.copyfile(W, bak)
    W.write_text(out, encoding="utf-8")
    print(f"patched: inserted missing except/pass | backup={bak.name}")
else:
    print("OK: no bare try blocks found")

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
        start = max(1, ln-25); end = ln+25
        txt = W.read_text(encoding="utf-8").splitlines()
        print(f"\n--- Ventana {start}-{end} ---")
        for k in range(start, min(end, len(txt))+1):
            print(f"{k:5d}: {txt[k-1]}")
    sys.exit(1)
