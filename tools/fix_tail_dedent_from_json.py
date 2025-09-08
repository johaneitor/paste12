#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)

def norm(s: str) -> str:
    s = s.replace("\r\n","\n").replace("\r","\n")
    if "\t" in s: s = s.replace("\t","    ")
    return s

def indw(line: str) -> int:
    return len(line) - len(line.lstrip(" "))

def gate():
    try:
        py_compile.compile(str(W), doraise=True)
        print("✓ py_compile OK"); return True
    except Exception as e:
        print("✗ py_compile FAIL:", e)
        tb = traceback.format_exc()
        m = re.search(r'__init__\.py, line (\d+)', tb)
        if m:
            ln = int(m.group(1))
            ctx = W.read_text(encoding="utf-8").splitlines()
            a = max(1, ln-40); b = min(len(ctx), ln+40)
            print(f"\n--- Ventana {a}-{b} ---")
            for k in range(a, b+1):
                print(f"{k:5d}: {ctx[k-1]}")
        return False

s = norm(W.read_text(encoding="utf-8"))
lines = s.split("\n")
n = len(lines)

# 1) indent base del chain if/elif action == "like"
pat_like = re.compile(r'^([ ]*)(?:if|elif)\s+action\s*==\s*[\'"]like[\'"]\s*:\s*$')
base_ws = ""
for i, L in enumerate(lines):
    m = pat_like.match(L)
    if m:
        base_ws = m.group(1)
        break
base = len(base_ws)

# 2) localizar la primera línea 'status, headers, body = _json('
pat_json = re.compile(r'^\s*status\s*,\s*headers\s*,\s*body\s*=\s*_json\(')
i_json = None
for i, L in enumerate(lines):
    if pat_json.match(L):
        i_json = i
        break

if i_json is None:
    print("✗ no hallé línea 'status, headers, body = _json('")
    sys.exit(1)

cur = indw(lines[i_json])
if cur <= base:
    print("OK: _json ya está alineado (no se cambia nada)")
    sys.exit(0)

delta = cur - base
changed = False

def shift_left(s: str, k: int) -> str:
    if not s.strip(): return s
    w = indw(s)
    if w == 0: return s
    new_w = max(0, w - k)
    return (" " * new_w) + s.lstrip(" ")

# 3) Desplazar a la izquierda desde i_json hasta EOF conservando offsets relativos
for j in range(i_json, n):
    before = lines[j]
    lines[j] = shift_left(lines[j], delta)
    if lines[j] != before:
        changed = True

if not changed:
    print("OK: nada que dedentar")
    sys.exit(0)

out = "\n".join(lines)
bak = W.with_suffix(".py.fix_tail_dedent.bak")
if not bak.exists():
    shutil.copyfile(W, bak)
W.write_text(out, encoding="utf-8")
print(f"patched: dedent desde _json(code,payload) (delta={delta}) | backup={bak.name}")

sys.exit(0 if gate() else 1)
