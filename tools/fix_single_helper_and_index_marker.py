#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
src = W.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n").replace("\r","\n").replace("\t","    ")

bak = W.with_suffix(".py.single_helper_fix.bak")
if not bak.exists():
    shutil.copyfile(W, bak)

changed = False

# 1) Elimina TODAS las definiciones existentes (aunque estén mal posicionadas)
src = re.sub(r'(?ms)^\s*def\s+_inject_single_attr\([^\)]*\):\s*.*?(?=^\S|\Z)', '', src)

# 2) Punto de inserción a nivel módulo (antes de _serve_index_html si existe, si no, al principio)
m_ins = re.search(r'(?m)^def\s+_serve_index_html\s*\(', src)
ins_at = m_ins.start() if m_ins else 0

helper = (
    "\n"
    "def _inject_single_attr(body, nid):\n"
    "    try:\n"
    "        b = body if isinstance(body, (bytes, bytearray)) else (body or b\"\")\n"
    "        if b:\n"
    "            return b.replace(b\"<body\", f'<body data-single=\"1\" data-note-id=\"{nid}\"'.encode(\"utf-8\"), 1)\n"
    "    except Exception:\n"
    "        pass\n"
    "    return body\n"
    "\n"
)

src2 = src[:ins_at] + helper + src[ins_at:]
if src2 != src:
    changed = True
    W.write_text(src2, encoding="utf-8")
    src = src2

# 3) Gate de compilación con ventana de contexto si falla
try:
    py_compile.compile(str(W), doraise=True)
    print("✓ backend helper OK | backup=", bak.name)
except Exception as e:
    print("✗ py_compile FAIL:", e)
    tb = traceback.format_exc()
    m = re.search(r'__init__\.py, line (\d+)', tb)
    if m:
        ln = int(m.group(1)); ctx = src.splitlines()
        a = max(1, ln-25); b = min(len(ctx), ln+25)
        print(f"\n--- Contexto {a}-{b} ---")
        for i in range(a, b+1):
            print(f"{i:5d}: {ctx[i-1]}")
    sys.exit(1)
