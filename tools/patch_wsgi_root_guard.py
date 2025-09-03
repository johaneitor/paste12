#!/usr/bin/env python3
import re, pathlib, py_compile, sys

P = pathlib.Path("wsgiapp/__init__.py")
s = P.read_text(encoding="utf-8")

# Ya está aplicado?
if "try:\n    _root_force_mw  # noqa" in s and "app = _root_force_mw(app)" not in s:
    print("guard ya presente; nada que hacer")
    sys.exit(0)

# Reemplazar cualquier 'app = _root_force_mw(app)' por un guard seguro (idempotente)
pattern = re.compile(r'^[ \t]*app[ \t]*=[ \t]*_root_force_mw\(app\)[ \t]*$', re.M)
guard = (
    "try:\n"
    "    _root_force_mw  # noqa\n"
    "except NameError:\n"
    "    pass\n"
    "else:\n"
    "    try:\n"
    "        app = _root_force_mw(app)\n"
    "    except Exception:\n"
    "        pass\n"
)

new_s, n = pattern.subn(guard, s)
if n == 0:
    # nada que reemplazar; no falles: solo informa
    print("no encontré 'app = _root_force_mw(app)' (ok)")
    sys.exit(0)

P.write_text(new_s, encoding="utf-8")

# Sanity: compilar
py_compile.compile(str(P), doraise=True)
print(f"reemplazos: {n} (ok)")
