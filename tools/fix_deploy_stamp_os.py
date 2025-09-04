#!/usr/bin/env python3
import re, sys, pathlib, py_compile

P = pathlib.Path("wsgiapp/__init__.py")
s = P.read_text(encoding="utf-8")

changed = False

# 1) Asegurar 'import os' y 'import json' (por si faltan)
if not re.search(r'^\s*import\s+os\b', s, flags=re.M):
    # Inserta tras el primer bloque de imports
    m = re.search(r'^(from[^\n]*\n|import[^\n]*\n)+', s, flags=re.M)
    if m:
        s = s[:m.end()] + "import os\n" + s[m.end():]
    else:
        s = "import os\n" + s
    changed = True

if not re.search(r'^\s*import\s+json\b', s, flags=re.M):
    m = re.search(r'^(from[^\n]*\n|import[^\n]*\n)+', s, flags=re.M)
    if m:
        s = s[:m.end()] + "import json\n" + s[m.end():]
    else:
        s = "import json\n" + s
    changed = True

# 2) Evitar sombreado local de 'os' dentro de funciones (p. ej. "os = ...", "except Exception as os")
#    - No tocamos líneas de import.
def _fix_shadow(match):
    indent = match.group(1)
    rest = match.group(2)
    return f"{indent}_os_local{rest}"

#   a) Asignaciones tipo "os = ..." al inicio lógico de línea
pat_assign = re.compile(r'^([ \t]*)os(\s*=\s*)', flags=re.M)
if pat_assign.search(s):
    s = pat_assign.sub(lambda m: f"{m.group(1)}_os_local{m.group(2)}", s)
    changed = True

#   b) 'except ... as os:'
s2, n2 = re.subn(r'(\bexcept\s+[^\n]*\s+as\s+)os(\s*:)', r'\1_os_exc\2', s)
if n2:
    s = s2
    changed = True

#   c) 'for os in ...:' (poco común, pero lo normalizamos)
s2, n3 = re.subn(r'(\bfor\s+)os(\s+in\s+)', r'\1_os_iter\2', s)
if n3:
    s = s2
    changed = True

# 3) Compilar antes de escribir
try:
    code = compile(s, str(P), 'exec')
except SyntaxError as e:
    print(f"✗ nuevo contenido no compila: {e}")
    sys.exit(2)

# 4) Escribir si cambió y verificar con py_compile
if changed:
    P.write_text(s, encoding="utf-8")

try:
    py_compile.compile(str(P), doraise=True)
    print("✓ __init__.py compila; fix aplicado" if changed else "✓ __init__.py compila; no cambios necesarios")
except Exception as e:
    print("✗ py_compile aún falla:", e)
    sys.exit(3)
