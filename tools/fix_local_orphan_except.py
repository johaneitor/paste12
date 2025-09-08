#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
s = W.read_text(encoding="utf-8")
s = s.replace("\r\n","\n").replace("\r","\n").replace("\t","    ")
lines = s.split("\n")
n = len(lines)
changed=False

# Delimitar un rango amplio alrededor del router (busca "/api/notes" y termina antes del siguiente "def " al inicio)
start = 0
for i,L in enumerate(lines):
    if "/api/notes" in L:
        start = max(0, i-200); break
end = n
for j in range(start+1, n):
    if re.match(r'^[ ]*def[ ]+\w+\(', lines[j]):
        end = j; break

def indw(x:str)->int: return len(x) - len(x.lstrip(" "))

i = start
while i < end:
    L = lines[i]
    if re.match(r'^[ ]*except\b.*:\s*$', L):
        base = indw(L)
        # busca hacia atrás un 'try:' al mismo indent
        k = i-1
        has_try=False
        while k >= start:
            T = lines[k]
            if T.strip()=="":
                k -= 1; continue
            if indw(T) < base:
                break
            if indw(T) == base and re.match(r'^[ ]*try:\s*$', T):
                has_try=True
            break
        if not has_try:
            lines.insert(i, " " * base + "try:")
            lines.insert(i+1, " " * (base+4) + "pass")
            changed=True
            i += 2
            end += 2
            continue
    i += 1

out = "\n".join(lines)
if changed:
    bak = W.with_suffix(".py.fix_local_orphan_except.bak")
    if not bak.exists():
        shutil.copyfile(W, bak)
    W.write_text(out, encoding="utf-8")
    print(f"patched: except huérfanos localmente arreglados | backup={bak.name}")
else:
    print("OK: no except huérfanos locales")

try:
    py_compile.compile(str(W), doraise=True)
    print("✓ py_compile OK")
except Exception as e:
    print("✗ py_compile falla:", e)
    tb = traceback.format_exc()
    m = re.search(r'__init__\\.py, line (\\d+)', tb)
    if m:
        ln = int(m.group(1))
        ctx = out.splitlines()
        a = max(1, ln-40); b = min(len(ctx), ln+40)
        print(f"\\n--- Ventana {a}-{b} ---")
        for k in range(a, b+1):
            print(f\"{k:5d}: {ctx[k-1]}\")
    sys.exit(1)
