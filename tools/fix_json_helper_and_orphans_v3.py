#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ wsgiapp/__init__.py no existe"); sys.exit(2)
raw = W.read_text(encoding="utf-8")

s = raw.replace("\r\n","\n").replace("\r","\n")
if "\t" in s: s = s.replace("\t","    ")
changed = (s != raw)

# --- A) Eliminar TODAS las defs previas de _json(...) ---
pat_drop_def = re.compile(r'(?ms)^[ \t]*def\s+_json\s*\([^)]*\)\s*:\s*(?:#.*)?\n(?:.*?\n)*?(?=^[^\s]|\Z)')
s2 = pat_drop_def.sub('', s); 
if s2 != s: s, changed = s2, True

# --- B) Eliminar restos del helper sueltos (body/status/headers/return) ---
pat_rest = re.compile(
    r'(?ms)^[ \t]*body\s*=\s*_json_mod\.dumps\([^\n]*\)\.encode\("utf-8"\)\n'
    r'(?:[ \t]*status\s*=\s*.*\n)?'
    r'(?:[ \t]*headers\s*=\s*\[.*?\]\n)?'
    r'[ \t]*return\s+status,\s*headers,\s*body\s*\n'
)
s2 = pat_rest.sub('', s)
if s2 != s: s, changed = s2, True

# --- C) Normalizar import json y alias seguro ---
# 1) import json as _json -> _json_mod
s2 = re.sub(r'(?m)^\s*import\s+json\s+as\s+_json\s*$', 'import json as _json_mod', s)
if s2 != s: s, changed = s2, True
# 2) from json import ... as _json -> _json_mod
s2 = re.sub(r'(?m)^\s*from\s+json\s+import\s+([A-Za-z0-9_,\s]+)\s+as\s+_json\s*$', r'from json import \1 as _json_mod', s)
if s2 != s: s, changed = s2, True
# 3) Si no hay ningún import json visible, añade alias
has_json = re.search(r'(?m)^\s*(?:from\s+json\s+import|import\s+json)\b', s) is not None
if not has_json:
    # Inserta tras docstring si existe, si no al inicio
    mdoc = re.match(r'\s*("""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\')\s*\n', s)
    ins = 'import json as _json_mod\n\n'
    if mdoc:
        s = s[:mdoc.end()] + ins + s[mdoc.end():]
    else:
        s = ins + s
    changed = True
# 4) Reescribir usos de _json.dumps/loads -> _json_mod
s2 = re.sub(r'\b_json\.(dumps|loads)\(', r'_json_mod.\1(', s)
if s2 != s: s, changed = s2, True

# --- D) Curar bloques huérfanos: def/if/for/while/try/... sin cuerpo ---
lines = s.split("\n")
open_kw = re.compile(r'^([ ]*)(def|class|if|elif|else|try|except|finally|for|while|with)\b.*:\s*(#.*)?$')
i = 0
inserted = 0
while i < len(lines):
    m = open_kw.match(lines[i])
    if not m:
        i += 1; continue
    base_indent = len(m.group(1))
    # buscar siguiente no-vacía
    j = i + 1
    while j < len(lines) and lines[j].strip() == "":
        j += 1
    if j >= len(lines) or len(lines[j]) - len(lines[j].lstrip(" ")) <= base_indent:
        # Inserta 'pass' con indent +4
        lines.insert(i+1, " "*(base_indent+4) + "pass")
        inserted += 1
        i += 2
    else:
        i = j
s2 = "\n".join(lines)
if s2 != s: s, changed = s2, True

# --- E) Insertar helper _json() a nivel top, tras imports ---
helper = (
"def _json(code, payload):\n"
"    \"\"\"(status, headers, body) JSON estándar, no-store, idempotente\"\"\"\n"
"    body = _json_mod.dumps(payload, default=str).encode(\"utf-8\")\n"
"    status = f\"{code} OK\"\n"
"    headers = [\n"
"        (\"Content-Type\", \"application/json; charset=utf-8\"),\n"
"        (\"Content-Length\", str(len(body))),\n"
"        (\"Cache-Control\", \"no-store, no-cache, must-revalidate, max-age=0\"),\n"
"        (\"X-WSGI-Bridge\", \"1\"),\n"
"    ]\n"
"    return status, headers, body\n"
""
)
# localizar bloque de imports del tope
m_imports = re.match(r'((?:\s*(?:from\s+\S+\s+import\s+.*|import\s+\S+.*)\n)+)', s)
ins_at = 0
if m_imports:
    ins_at = m_imports.end()
    if not s[ins_at:ins_at+1].startswith("\n"):
        helper = "\n" + helper
else:
    mdoc = re.match(r'\s*("""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\')\s*\n', s)
    if mdoc: ins_at = mdoc.end()

# Asegurar dos saltos antes si no estamos al inicio exacto
prefix = s[:ins_at]
suffix = s[ins_at:]
if not prefix.endswith("\n\n"):
    if not prefix.endswith("\n"):
        prefix += "\n"
    prefix += "\n"
s = prefix + helper + "\n\n" + suffix
changed = True

# --- F) Guardar + backup + gate ---
if changed:
    bak = W.with_suffix(".py.fix_json_orphans_v3.bak")
    if not bak.exists():
        shutil.copyfile(W, bak)
    W.write_text(s, encoding="utf-8")
    print(f"patched: json helper reescrito + orphans fixed (inserted pass x{inserted}) | backup={bak.name}")
else:
    print("OK: no se requirieron cambios (nada que hacer)")

try:
    py_compile.compile(str(W), doraise=True)
    print("✓ py_compile OK")
except Exception as e:
    print("✗ py_compile falla:", e)
    tb = traceback.format_exc()
    m = re.search(r'__init__\.py, line (\d+)', tb)
    if m:
        ln = int(m.group(1))
        start = max(1, ln-20); end = ln+20
        txt = W.read_text(encoding="utf-8").splitlines()
        print(f"\n--- Ventana {start}-{end} ---")
        for k in range(start, min(end, len(txt))+1):
            print(f"{k:5d}: {txt[k-1]}")
    sys.exit(1)
