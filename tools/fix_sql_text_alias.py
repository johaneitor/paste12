#!/usr/bin/env python3
import re, sys, pathlib, py_compile, shutil
W = pathlib.Path("wsgiapp/__init__.py")
s = W.read_text(encoding="utf-8")
orig = s

changed = False

# 1) Asegurar import de sqlalchemy.text como _text
imp_re = re.compile(r'(?m)^from\s+sqlalchemy\s+import\s+text\s+as\s+_text\s*$')
if not imp_re.search(s):
    # Inserta al inicio, después de un posible shebang o docstring corto
    insert_at = 0
    # salta shebang
    if s.startswith("#!"):
        insert_at = s.find("\n") + 1
    # tras docstring triple si está al comienzo
    m = re.match(r'\A\s*(?P<q>["\']{3}).*?(?P=q)\s*', s, flags=re.S)
    if m:
        insert_at = m.end()
    s = s[:insert_at] + "\nfrom sqlalchemy import text as _text\n" + s[insert_at:]
    changed = True

# 2) Asegurar alias T = _text si en el código aparece T(…)
if re.search(r'(?<![A-Za-z0-9_])T\(', s):
    # si ya existe T = _text, no duplicar
    if "T = _text" not in s:
        # colocarlo justo después del import _text
        m = re.search(r'(?m)^from\s+sqlalchemy\s+import\s+text\s+as\s+_text\s*$', s)
        if m:
            pos = m.end()
            s = s[:pos] + "\nT = _text" + s[pos:]
            changed = True

# 3) Guardar sólo si cambió, con backup
if not changed:
    print("OK: import y alias ya presentes; sin cambios.")
else:
    bak = W.with_suffix(".py.sqlalias.bak")
    if not bak.exists():
        shutil.copyfile(W, bak)
    W.write_text(s, encoding="utf-8")
    print(f"patched: import/alias (backup: {bak.name})")

# 4) Gate de compilación
py_compile.compile(str(W), doraise=True)
print("✓ py_compile OK")
