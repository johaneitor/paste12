#!/usr/bin/env python3
import re, pathlib, shutil, sys, py_compile

W = pathlib.Path("wsgiapp/__init__.py")
src = W.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n").replace("\r","\n")

bak = W.with_suffix(".single_head_meta.bak")
if not bak.exists():
    shutil.copyfile(W, bak)

# Buscamos el bloque donde ya se inyecta data-single en <body>
pat = re.compile(
    r'(\n[ \t]*if[ \t]+_id:[^\n]*\n'          # if _id:
    r'(?:[ \t]+[^\n]*\n){0,8}?'               # unas pocas líneas dentro
    r'[ \t]*_b[ \t]*=[ \t]*body[^\n]*\n'      # _b = body...
    r'[ \t]*_b[ \t]*=[ \t]*_b\.replace\([^\n]*<body[^\n]*\)\n)'  # replace <body ... data-single...
, re.M)

def inject(m):
    head_inj = (
        "        # aseguro meta p12-single en <head> (solo si no existe)\n"
        "        try:\n"
        "            if b'</head>' in _b and b'name=\"p12-single\"' not in _b:\n"
        "                _b = _b.replace(b'</head>', b'<meta name=\"p12-single\" content=\"1\"></head>', 1)\n"
        "        except Exception:\n"
        "            pass\n"
    )
    return m.group(1) + head_inj

src2, n = pat.subn(inject, src, count=1)
if n == 0:
    print("✗ no encontré el bloque de inyección de data-single; no modifiqué nada")
    sys.exit(1)

W.write_text(src2, encoding="utf-8")

try:
    py_compile.compile(str(W), doraise=True)
    print("✓ backend listo (meta p12-single server-side) | backup=", bak.name)
except Exception as e:
    print("✗ py_compile FAIL:", e); sys.exit(1)
