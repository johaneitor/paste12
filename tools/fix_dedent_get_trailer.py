#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)

def norm(s: str) -> str:
    s = s.replace("\r\n","\n").replace("\r","\n")
    if "\t" in s: s = s.replace("\t","    ")
    return s

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

# Anclas: POST (para tomar el indent “bueno”) y GET (para comenzar a dedentar)
re_post = re.compile(r'^([ ]*)if\s+path\.startswith\(\s*[\'"]/api/notes/[\'"]\s*\)\s+and\s+method\s*==\s*[\'"]POST[\'"]\s*:\s*$', re.M)
re_get  = re.compile(r'^([ ]*)if\s+path\.startswith\(\s*[\'"]/api/notes/[\'"]\s*\)\s+and\s+method\s*==\s*[\'"]GET[\'"]\s*:\s*$',  re.M)

mp = re_post.search(s)
mg = re_get.search(s)
if not mp or not mg:
    print("✗ no pude localizar los bloques POST/GET ancla"); sys.exit(1)

want_ws = mp.group(1)                 # indent “deseado”
have_ws = mg.group(1)                 # indent actual del GET
delta   = len(have_ws) - len(want_ws) # cuánto hay que dedentar

if delta <= 0:
    print("OK: GET ya está al nivel correcto (no se cambia nada)")
    sys.exit(0)

lines = s.split("\n")
# índice (0-based) de la línea del GET
get_line_idx = s[:mg.start()].count("\n")

# Dedentar desde GET hasta EOF por 'delta' espacios (si existen)
changed = False
for i in range(get_line_idx, len(lines)):
    L = lines[i]
    # sólo dedentamos si realmente tiene >= delta espacios iniciales
    if L.startswith(" " * delta):
        lines[i] = L[delta:]
        changed = True
    elif L.strip() == "":
        # líneas en blanco: normalizamos a blanco simple
        lines[i] = ""
        changed = True
    else:
        # si no tiene tantos espacios, no tocamos esa línea
        pass

if not changed:
    print("OK: nada para dedentar")
    sys.exit(0)

out = "\n".join(lines)

bak = W.with_suffix(".py.fix_dedent_get_trailer.bak")
if not bak.exists():
    shutil.copyfile(W, bak)
W.write_text(out, encoding="utf-8")
print(f"patched: dedent aplicado desde bloque GET | backup={bak.name}")

if not gate():
    sys.exit(1)
