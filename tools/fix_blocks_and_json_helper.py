#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ wsgiapp/__init__.py no existe"); sys.exit(2)

raw = W.read_text(encoding="utf-8")
s = raw
changed = False

# -------------------------------------------------------------------
# A) Normalizar tabs -> 4 spaces
# -------------------------------------------------------------------
if "\t" in s:
    s = s.replace("\t", "    ")
    changed = True

# -------------------------------------------------------------------
# B) Resolver shadowing de json:  _json (módulo) → _json_mod
# -------------------------------------------------------------------
pat_import1 = re.compile(r'^\s*import\s+json\s+as\s+_json\s*$', re.M)
pat_import2 = re.compile(r'^\s*from\s+json\s+import\s+([A-Za-z0-9_,\s]+)\s+as\s+_json\s*$', re.M)

if pat_import1.search(s):
    s = pat_import1.sub('import json as _json_mod', s); changed = True
if pat_import2.search(s):
    s = pat_import2.sub(r'from json import \1 as _json_mod', s); changed = True

# Usos del módulo
s2 = re.sub(r'\b_json\.(dumps|loads)\(', r'_json_mod.\1(', s)
if s2 != s: s, changed = s2, True

# -------------------------------------------------------------------
# C) Garantizar función helper _json(code, payload) (si no existe)
#     y que use _json_mod.dumps
# -------------------------------------------------------------------
helper_fn = r'''
def _json(code, payload):
    """Devuelve (status, headers, body) para JSON con no-store; usa _json_mod.dumps."""
    try:
        import json as _json_mod  # fallback
    except Exception:
        import json as _json_mod
    body = _json_mod.dumps(payload, default=str).encode("utf-8")
    status = f"{code} OK"
    headers = [
        ("Content-Type", "application/json; charset=utf-8"),
        ("Content-Length", str(len(body))),
        ("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0"),
        ("X-WSGI-Bridge", "1"),
    ]
    return status, headers, body
'''.lstrip('\n')

if not re.search(r'(?m)^\s*def\s+_json\s*\(', s):
    # Insertar tras bloque de imports si existe; si no, al principio
    m = re.search(r'^(?:from\s+\S+\s+import\s+.*\n|import\s+\S+.*\n)+', s, flags=re.M)
    if m:
        s = s[:m.end()] + "\n" + helper_fn + "\n" + s[m.end():]
    else:
        s = helper_fn + "\n" + s
    changed = True
else:
    s2 = re.sub(r'(^\s*def\s+_json\s*\([^\)]*\):[\s\S]*?)\b(json|_json)\.dumps\(',
                r'\1_json_mod.dumps(', s, flags=re.M)
    if s2 != s: s, changed = s2, True

# -------------------------------------------------------------------
# D) Curar bloques huérfanos que causan IndentationError
#     - def/class/if/elif/else/for/while/try/except/finally/with sin cuerpo
#     - Insertamos 'pass' con indent base+4
#     - Saltamos dentro de triple quotes """ o '''
# -------------------------------------------------------------------
lines = s.split("\n")
n = len(lines)
out = []
i = 0

triple = None  # None | '"""' | "'''"

def toggle_triple_quote(line, triple):
    # Detección simple: cuenta apariciones no escapadas del mismo delimitador
    for q in ('"""',"'''"):
        cnt = 0
        j = 0
        while True:
            k = line.find(q, j)
            if k < 0: break
            # ignorar \"\"\" o \''' (escapadas)
            if k == 0 or line[k-1] != '\\':
                cnt += 1
            j = k + len(q)
        if cnt % 2 == 1:  # impar -> alterna
            if triple is None:
                triple = q
            elif triple == q:
                triple = None
    return triple

# Regex para encabezados sin código en la misma línea (solo comentario opcional)
re_defclass = re.compile(r'^([ ]*)(def|class)\s+[A-Za-z_][A-Za-z0-9_]*\s*(\([^)]*\))?\s*:\s*(#.*)?$')
re_ctrl = re.compile(r'^([ ]*)(if|elif|else|for|while|try|except|finally|with)\b[^\n]*:\s*(#.*)?$')

def first_code_line_after(idx):
    """Primera línea > idx que no sea vacía ni solo comentario."""
    j = idx + 1
    while j < n:
        t = lines[j].strip()
        if t != "" and not t.startswith("#"):
            return j
        j += 1
    return None

while i < n:
    line = lines[i]
    # Estado de triple-quote
    triple = toggle_triple_quote(line, triple)
    out.append(line)
    if triple is None:
        m = re_defclass.match(line) or re_ctrl.match(line)
        if m:
            base = len(m.group(1))
            j = first_code_line_after(i)
            need_pass = False
            if j is None:
                need_pass = True
            else:
                # Si la primera línea de código no está más indentada, es huérfana
                indent_next = len(lines[j]) - len(lines[j].lstrip(" "))
                if indent_next <= base:
                    need_pass = True
            if need_pass:
                out.append(" "*(base+4) + "pass")
                changed = True
    i += 1

s_fixed = "\n".join(out)
if s_fixed != s:
    s = s_fixed

# Asegurar newline al final
if not s.endswith("\n"):
    s += "\n"

# -------------------------------------------------------------------
# E) Guardar y gatear
# -------------------------------------------------------------------
if s == raw:
    print("OK: no hubo cambios (o ya estaba sano). Probando compilación de todas formas…")
else:
    bak = W.with_suffix(".py.fix_blocks_json.bak")
    if not bak.exists():
        shutil.copyfile(W, bak)
    W.write_text(s, encoding="utf-8")
    print("patched: normalización + helper _json + bloques huérfanos reparados")

try:
    py_compile.compile(str(W), doraise=True)
    print("✓ py_compile OK")
except Exception as e:
    # Mostrar ventana alrededor del error que reporta py_compile
    print("✗ py_compile falla:", e)
    # Intentar extraer número de línea del mensaje
    import traceback
    tb = traceback.format_exc()
    import re as _re
    m = _re.search(r'__init__\.py, line (\d+)', tb)
    if m:
        ln = int(m.group(1))
        start = max(1, ln-15); end = ln+15
        txt = W.read_text(encoding="utf-8").splitlines()
        print(f"\n--- Ventana {start}-{end} ---")
        for k in range(start, min(end, len(txt))+1):
            print(f"{k:5d}: {txt[k-1]}")
    sys.exit(1)
