#!/usr/bin/env python3
import sys, pathlib, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
try:
    py_compile.compile(str(W), doraise=True)
    print("✓ compile OK (sin errores)")
    sys.exit(0)
except Exception as e:
    print("✗ compile FAIL:", e)
    # Intentamos extraer línea
    tb = e.exc_traceback if hasattr(e, "exc_traceback") else None
    # py_compile envuelve el error; buscamos "line XXX" en el str
    import re
    m = re.search(r'line (\d+)', str(e))
    line = int(m.group(1)) if m else None
    txt = W.read_text(encoding="utf-8", errors="replace").splitlines()
    if line:
        lo = max(1, line-10); hi = min(len(txt), line+10)
        print(f"\n--- {W} contexto {lo}-{hi} (→ falla en línea {line}) ---")
        for i in range(lo, hi+1):
            mark = ">>" if i == line else "  "
            print(f"{mark} {i:5d}: {txt[i-1]}")
    else:
        print("\n(no pude inferir línea; mira el mensaje de arriba)")
    sys.exit(1)
