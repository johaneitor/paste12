#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ wsgiapp/__init__.py no existe"); sys.exit(2)

raw = W.read_text(encoding="utf-8")
s = raw.replace("\r\n","\n").replace("\r","\n")
if "\t" in s: s = s.replace("\t","    ")
changed = s != raw

lines = s.split("\n")

# ---- A) Asegurar import json as _json_mod a nivel módulo (una sola vez) ----
has_top_import = re.search(r'(?m)^\s*import\s+json\s+as\s+_json_mod\s*$', s) is not None
if not has_top_import:
    # Insertar tras bloque de imports superior o tras docstring
    ins = "import json as _json_mod\n"
    m_imports = re.match(r'((?:\s*(?:from\s+\S+\s+import\s+.*|import\s+\S+.*)\n)+)', s)
    if m_imports:
        pos = m_imports.end()
        s = s[:pos] + ("" if s[pos:pos+1] == "\n" else "\n") + ins + s[pos:]
    else:
        mdoc = re.match(r'\s*(\"\"\"[\s\S]*?\"\"\"|\'\'\'[\s\S]*?\'\'\')\s*\n', s)
        if mdoc:
            pos = mdoc.end()
            s = s[:pos] + ins + s[pos:]
        else:
            s = ins + s
    changed = True
    lines = s.split("\n")

# ---- B) Limpiar cualquier "import json as _json_mod" dentro de la clase ----
out = []
in_class = False
class_indent = 0
for i, ln in enumerate(lines):
    m_cls = re.match(r'^([ ]*)class\s+_AcceptJsonOrFormNotes\b', ln)
    if m_cls:
        in_class = True
        class_indent = len(m_cls.group(1))
        out.append(ln); continue
    if in_class:
        # ¿salimos de la clase?
        if ln.strip() and (len(ln) - len(ln.lstrip(" ")) <= class_indent):
            in_class = False
        else:
            # si es un import json as _json_mod dentro de la clase, dropearlo
            if re.match(r'^[ ]*import\s+json\s+as\s+_json_mod\s*$', ln):
                changed = True
                continue
    out.append(ln)
lines = out
s = "\n".join(lines)

# ---- C) Reescribir el cuerpo de def _resp_json(...) con indent correcto ----
lines = s.split("\n")
out = []
i = 0
modified_resp = False
def_re = re.compile(r'^([ ]*)def\s+_resp_json\s*\(\s*self\s*,\s*start_response\s*,\s*code\s*,\s*payload\s*\)\s*:\s*$')
while i < len(lines):
    m = def_re.match(lines[i])
    if not m:
        out.append(lines[i]); i += 1; continue
    base = m.group(1)  # indent de la def
    out.append(lines[i]); i += 1
    # saltar interior viejo hasta el siguiente bloque con indent <= base (o EOF)
    j = i
    while j < len(lines):
        ln = lines[j]
        if ln.strip() != "" and (len(ln) - len(ln.lstrip(" ")) <= len(base)):
            break
        j += 1
    # reemplazar cuerpo por el canónico
    body = [
        f"{base}    body = _json_mod.dumps(payload, default=str).encode(\"utf-8\")",
        f"{base}    start_response(f\"{{code}} OK\", [",
        f"{base}        (\"Content-Type\",\"application/json; charset=utf-8\"),",
        f"{base}        (\"Content-Length\", str(len(body))),",
        f"{base}        (\"Cache-Control\", \"no-store, no-cache, must-revalidate, max-age=0\"),",
        f"{base}        (\"X-WSGI-Bridge\",\"1\"),",
        f"{base}    ])",
        f"{base}    return [body]",
    ]
    out.extend(body)
    i = j
    modified_resp = True

if modified_resp:
    s2 = "\n".join(out)
    if s2 != s:
        s = s2
        changed = True

# ---- D) Guardar + backup + gate ----
if changed:
    bak = W.with_suffix(".py.fix_accept_json_resp_v2.bak")
    if not bak.exists():
        shutil.copyfile(W, bak)
    W.write_text(s, encoding="utf-8")
    print(f"patched: _AcceptJsonOrFormNotes._resp_json y json import | backup={bak.name}")
else:
    print("OK: no se requirieron cambios")

try:
    py_compile.compile(str(W), doraise=True)
    print("✓ py_compile OK")
except Exception as e:
    print("✗ py_compile falla:", e)
    tb = traceback.format_exc()
    m = re.search(r'__init__\.py, line (\d+)', tb)
    if m:
        ln = int(m.group(1))
        start = max(1, ln-25); end = ln+25
        txt = W.read_text(encoding="utf-8").splitlines()
        print(f"\n--- Ventana {start}-{end} ---")
        for k in range(start, min(end, len(txt))+1):
            print(f"{k:5d}: {txt[k-1]}")
    sys.exit(1)
