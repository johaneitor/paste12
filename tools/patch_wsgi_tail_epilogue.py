#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)

def norm(s: str) -> str:
    s = s.replace("\r\n","\n").replace("\r","\n")
    return s.replace("\t","    ")

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
            a = max(1, ln-35); b = min(len(ctx), ln+35)
            print(f"\n--- Ventana {a}-{b} ---")
            for k in range(a, b+1):
                print(f"{k:5d}: {ctx[k-1]}")
        return False

src = norm(W.read_text(encoding="utf-8"))

# --- localiza una "cola" sospechosa a partir de cualquiera de estos anclajes ---
anchors = [
    r'^\s*return\s+_app\s*$',
    r'^\s*_app\s*=\s*_resolve_app\s*\(',
    r'^\s*app\s*=\s*_middleware\s*\(',
    r'^\s*if\s+inner_app\s+is\s+not\s+None\s*:\s*$',
]
spots = []
for pat in anchors:
    for m in re.finditer(pat, src, re.M):
        spots.append(m.start())
start = min(spots) if spots else None   # si hay varios, nos quedamos con el primero que delata cola mal indentada

EPILOGUE = r'''
# --- WSGI entrypoint (nivel módulo) ---
try:
    _app = _resolve_app()  # type: ignore[name-defined]
except Exception:
    _app = None  # fallback
app  = _middleware(_app, is_fallback=(_app is None))  # type: ignore[name-defined]

# Aplica _root_force_mw si existe (CORS/OPTIONS y otros hooks)
try:
    _root_force_mw  # noqa: F821
except NameError:
    pass
else:
    try:
        app = _root_force_mw(app)  # type: ignore[name-defined]
    except Exception:
        # no rompas el entrypoint si el mw falla
        pass
'''.lstrip("\n")

if start is None:
    # no encontramos anclajes; añadimos el epílogo limpio al final
    new = src.rstrip() + "\n\n" + EPILOGUE
else:
    # sustituimos desde el primer anclaje hasta EOF por el epílogo canónico
    new = src[:start].rstrip() + "\n\n" + EPILOGUE

if new == src:
    print("OK: epílogo ya parecía canónico (sin cambios)")
    if not gate(): sys.exit(1)
    sys.exit(0)

bak = W.with_suffix(".py.fix_wsgi_tail_epilogue.bak")
if not bak.exists():
    shutil.copyfile(W, bak)
W.write_text(new, encoding="utf-8")
print(f"patched: epílogo WSGI canónico inyectado | backup={bak.name}")

if not gate(): sys.exit(1)
