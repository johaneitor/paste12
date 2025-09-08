#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ wsgiapp/__init__.py no existe"); sys.exit(2)

def norm(txt: str) -> str:
    txt = txt.replace("\r\n","\n").replace("\r","\n")
    if "\t" in txt: txt = txt.replace("\t","    ")
    return txt

raw = W.read_text(encoding="utf-8")
s = norm(raw)
lines = s.split("\n")
n = len(lines)
changed = False

def indw(l: str) -> int: return len(l) - len(l.lstrip(" "))
def next_nonempty(i: int) -> int:
    j = i + 1
    while j < n and lines[j].strip() == "":
        j += 1
    return j

hdr_re = re.compile(r'^(except\b.*:|finally:)\s*$')
block_hdr_re = re.compile(r'^(except\b|finally\b|elif\b|else\b|except:)\b')

i = 0
while i < n:
    L = lines[i]
    m = hdr_re.match(L.lstrip())
    if m and indw(L) == indw(L):  # sólo para silencio del linter :)
        base = indw(L)
        body_i = next_nonempty(i)
        # Si EOF tras header, insertamos 'pass'
        if body_i >= n:
            lines.append(" "*(base+4) + "pass")
            changed = True
            n = len(lines)
            break
        body_line = lines[body_i]
        # Si el siguiente también es header de bloque al mismo o menor indent → falta cuerpo: insert pass
        if indw(body_line) <= base and block_hdr_re.match(body_line.lstrip()):
            lines.insert(body_i, " "*(base+4) + "pass")
            changed = True
            n += 1
            i = body_i + 1
            continue
        # Si el “cuerpo” actual NO está indentado más que el header → reindent
        if indw(body_line) <= base:
            lines[body_i] = " "*(base+4) + body_line.lstrip(" ")
            changed = True
            i = body_i + 1
            continue
        i = body_i
        continue
    i += 1

out = "\n".join(lines)
if changed:
    bak = W.with_suffix(".py.fix_except_body_indent_v2.bak")
    if not bak.exists():
        shutil.copyfile(W, bak)
    W.write_text(out, encoding="utf-8")
    print(f"patched: except/finally body indent fixed | backup={bak.name}")
else:
    print("OK: no except/finally mal indentados detectados")

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
        ctx = out.splitlines()
        a = max(1, ln-30); b = min(len(ctx), ln+30)
        print(f"\n--- Ventana {a}-{b} ---")
        for k in range(a, b+1):
            print(f"{k:5d}: {ctx[k-1]}")
    sys.exit(1)
