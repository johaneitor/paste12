#!/usr/bin/env python3
import re, sys, traceback, py_compile, pathlib
W = pathlib.Path("wsgiapp/__init__.py")
try:
    py_compile.compile(str(W), doraise=True)
    print("✓ py_compile OK")
    sys.exit(0)
except Exception as e:
    tb = traceback.format_exc()
    print("✗ py_compile FAIL\n")
    print(tb)
    # intenta extraer línea con varios patrones
    m = (re.search(r'__init__\.py, line (\d+)', tb) or
         re.search(r'File ".*__init__\.py", line (\d+)', tb) or
         re.search(r'line (\d+)', tb))
    if not m:
        sys.exit(1)
    ln = int(m.group(1))
    txt = W.read_text(encoding="utf-8").splitlines()
    a = max(1, ln-40); b = min(len(txt), ln+40)
    print(f"\n--- Ventana {a}-{b} ---")
    for i in range(a, b+1):
        print(f"{i:5d}: {txt[i-1]}")
    sys.exit(1)
