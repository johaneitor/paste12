#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ wsgiapp/__init__.py no existe"); sys.exit(2)

raw = W.read_text(encoding="utf-8")

# --- Normalizaciones básicas ---
s = raw.replace("\r\n", "\n").replace("\r", "\n")
if "\t" in s:
    s = s.replace("\t", "    ")

changed = (s != raw)

# --- 1) Quitar TODAS las defs previas de _json(...) (buenas o rotas) ---
# Captura desde 'def _json(...) :' hasta la próxima línea de columna 0 (o EOF)
pat_drop = re.compile(r'(?ms)^[ \t]*def\s+_json\s*\([^)]*\)\s*:\s*(?:#.*)?\n(?:.*?\n)*?(?=^[^\s]|\Z)')
s2 = pat_drop.sub('', s)
if s2 != s:
    s, changed = s2, True

# --- 2) Arreglar import json y usos del alias ---
# Evitar sombra: si hay 'import json as _json' u otros, pasarlos a _json_mod
pat_imp1 = re.compile(r'(?m)^\s*import\s+json\s+as\s+_json\s*$')
pat_imp2 = re.compile(r'(?m)^\s*from\s+json\s+import\s+([A-Za-z0-9_,\s]+)\s+as\s+_json\s*$')

s2 = pat_imp1.sub('import json as _json_mod', s)
if s2 != s: s, changed = s2, True
s2 = pat_imp2.sub(r'from json import \1 as _json_mod', s)
if s2 != s: s, changed = s2, True

# Si no hay ningún import para json, añade uno seguro al tope tras docstring si existe
has_json_mod = re.search(r'(?m)^\s*(import|from)\s+json\b', s) is not None
if not has_json_mod:
    # Insertar tras docstring ("""...""") si está al principio, o al inicio del archivo
    mdoc = re.match(r'\s*("""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\')\s*\n', s)
    ins = 'import json as _json_mod\n\n'
    if mdoc:
        idx = mdoc.end()
        s = s[:idx] + ins + s[idx:]
    else:
        s = ins + s
    changed = True

# Arreglar usos del alias antiguo
s2 = re.sub(r'\b_json\.(dumps|loads)\(', r'_json_mod.\1(', s)
if s2 != s: s, changed = s2, True

# --- 3) Insertar helper _json(...) canónico a nivel top (siempre, ya borramos anteriores) ---
helper = (
    "def _json(code, payload):\n"
    "    \"\"\"Devuelve (status, headers, body) JSON con no-store (idempotente).\"\"\"\n"
    "    body = _json_mod.dumps(payload, default=str).encode(\"utf-8\")\n"
    "    status = f\"{code} OK\"\n"
    "    headers = [\n"
    "        (\"Content-Type\", \"application/json; charset=utf-8\"),\n"
    "        (\"Content-Length\", str(len(body))),\n"
    "        (\"Cache-Control\", \"no-store, no-cache, must-revalidate, max-age=0\"),\n"
    "        (\"X-WSGI-Bridge\", \"1\"),\n"
    "    ]\n"
    "    return status, headers, body\n"
    "\n"
)

# Insertarlo tras el bloque de imports iniciales si existen; si no, al principio
imports_block = re.match(r'((?:\s*(?:from\s+\S+\s+import\s+.*|import\s+\S+.*)\n)+)', s)
insert_at = 0
if imports_block:
    insert_at = imports_block.end()
    # Deja una línea en blanco antes si no hay
    if not s[insert_at:insert_at+1].startswith("\n"):
        helper = "\n" + helper
else:
    # Si empezamos con docstring, insertamos tras docstring (ya revisado antes)
    mdoc = re.match(r'\s*("""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\')\s*\n', s)
    if mdoc:
        insert_at = mdoc.end()

s = s[:insert_at] + helper + s[insert_at:]
changed = True

# --- 4) Guardar y gatear ---
if changed:
    bak = W.with_suffix(".py.rewrite_json_helper_top.bak")
    if not bak.exists():
        shutil.copyfile(W, bak)
    W.write_text(s, encoding="utf-8")
    print("patched: reescrito _json top-level + normalizaciones (backup creado)")
else:
    print("OK: no se requirieron cambios")

# Compile gate + ventana si fallara
try:
    py_compile.compile(str(W), doraise=True)
    print("✓ py_compile OK")
except Exception as e:
    print("✗ py_compile falla:", e)
    import traceback, re as _re
    tb = traceback.format_exc()
    m = _re.search(r'__init__\.py, line (\d+)', tb)
    if m:
        ln = int(m.group(1))
        start = max(1, ln-15); end = ln+15
        txt = W.read_text(encoding="utf-8").splitlines()
        print(f"\n--- Ventana {start}-{end} ---")
        for k in range(start, min(end, len(txt))+1):
            print(f"{k:5d}: {txt[k-1]}")
    sys.exit(1)
