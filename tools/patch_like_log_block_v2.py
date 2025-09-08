#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ wsgiapp/__init__.py no existe"); sys.exit(2)

def norm(s: str) -> str:
    s = s.replace("\r\n","\n").replace("\r","\n")
    if "\t" in s: s = s.replace("\t","    ")
    return s

s = norm(W.read_text(encoding="utf-8"))
lines = s.split("\n")
n = len(lines)

def indw(l: str) -> int:
    return len(l) - len(l.lstrip(" "))

# 1) localizar el bloque por el DDL de like_log
ddl_pat = re.compile(r'CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+like_log\(', re.I)
pos = None
for i, L in enumerate(lines):
    if ddl_pat.search(L):
        pos = i
        break

if pos is None:
    print("OK: no se encontró DDL de like_log (nada que tocar)")
    sys.exit(0)

# 2) buscar el "with _engine().begin() as cx" hacia arriba
with_idx = None
for i in range(pos, -1, -1):
    if 'with _engine().begin() as cx' in lines[i]:
        with_idx = i
        break
if with_idx is None:
    print("✗ No hallé 'with _engine().begin() as cx' arriba del DDL; aborto")
    sys.exit(2)

# 3) tomar como inicio el try: inmediatamente anterior (si existe al mismo nivel o menos)
base_w = indw(lines[with_idx])
start = None
for i in range(with_idx, -1, -1):
    L = lines[i]
    if re.match(r'^\s*try:\s*$', L) and indw(L) <= base_w:
        start = i
        break
if start is None:
    # si no hay try, empezamos en el 'with'
    start = with_idx

# 4) fin del bloque: justo antes de la primera línea con 'fp = _fingerprint(' (marca de fin)
end = None
for i in range(pos, min(n, pos+400)):  # ventana razonable
    if 'fp = _fingerprint(' in lines[i]:
        end = i
        break
if end is None:
    print("✗ No hallé 'fp = _fingerprint(' después del DDL; aborto")
    sys.exit(2)

indent = " " * indw(lines[start])

canonical = f"""{indent}try:
{indent}    from sqlalchemy import text as _text
{indent}    with _engine().begin() as cx:
{indent}        try:
{indent}            cx.execute(_text(\"\"\"CREATE TABLE IF NOT EXISTS like_log(
{indent}                note_id INTEGER NOT NULL REFERENCES note(id) ON DELETE CASCADE,
{indent}                fingerprint VARCHAR(128) NOT NULL,
{indent}                created_at TIMESTAMPTZ DEFAULT NOW(),
{indent}                PRIMARY KEY (note_id, fingerprint)
{indent}            )\"\"\"))
{indent}        except Exception:
{indent}            pass
{indent}        try:
{indent}            cx.execute(_text(\"\"\"CREATE UNIQUE INDEX IF NOT EXISTS uq_like_note_fp
{indent}            ON like_log(note_id, fingerprint)\"\"\"))
{indent}        except Exception:
{indent}            pass
{indent}except Exception:
{indent}    pass
"""

# 5) aplicar reemplazo
new_lines = lines[:start] + canonical.rstrip("\n").split("\n") + lines[end:]
out = "\n".join(new_lines)

if out == s:
    print("OK: nada que cambiar")
    sys.exit(0)

bak = W.with_suffix(".py.patch_like_log_block_v2.bak")
if not bak.exists():
    shutil.copyfile(W, bak)
W.write_text(out, encoding="utf-8")
print(f"patched: like_log DDL block normalizado | backup={bak.name}")

# 6) gate de compilación
try:
    py_compile.compile(str(W), doraise=True)
    print("✓ py_compile OK")
except Exception as e:
    print("✗ py_compile falla:", e)
    tb = traceback.format_exc()
    m = re.search(r'__init__\.py, line (\d+)', tb)
    if m:
        ln = int(m.group(1))
        ctx = out.splitlines()
        a = max(1, ln-30); b = min(len(ctx), ln+30)
        print(f"\n--- Ventana {a}-{b} ---")
        for k in range(a, b+1):
            print(f"{k:5d}: {ctx[k-1]}")
    sys.exit(1)
