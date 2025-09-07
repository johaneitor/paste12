#!/usr/bin/env python3
import pathlib, py_compile, shutil, sys

W = pathlib.Path("wsgiapp/__init__.py")
F = pathlib.Path("tools/auth_block_min.pyfrag")

if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)
if not F.exists():
    print("✗ no existe tools/auth_block_min.pyfrag"); sys.exit(2)

raw = W.read_text(encoding="utf-8")
frag = F.read_text(encoding="utf-8")

if "class _AuthEndpoints" in raw:
    try:
        py_compile.compile(str(W), doraise=True)
        print("OK: _AuthEndpoints ya presente y compila.")
        sys.exit(0)
    except Exception as e:
        print("AVISO: presente pero no compila:", e)

# Append-only + salto de línea
s = raw
if not s.endswith("\n"):
    s += "\n"
s += "\n" + frag.strip("\n") + "\n"

bak = W.with_suffix(".py.auth_patch_v3.bak")
if not bak.exists():
    shutil.copyfile(W, bak)

W.write_text(s, encoding="utf-8")

try:
    py_compile.compile(str(W), doraise=True)
    print("patched: auth v3 desde fragmento + compile OK; backup:", bak)
except Exception as e:
    print("✗ compile tras patch:", e)
    print("Revirtiendo al backup:", bak)
    shutil.copyfile(bak, W)
    sys.exit(1)
