#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, importlib

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists(): print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)
src = W.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n")

if "def _compose_with_ext(" in src and "app = _compose_with_ext(" in src:
    print("OK: ext mounts ya habilitados"); sys.exit(0)

BLOCK = r'''
def _compose_with_ext(app):
    """
    Monta apps externas bajo prefijos, a partir de EXT_APPS.
    Formatos aceptados (separar múltiples por comas):
      - "mipkg.mod:app@/ext/foo"
      - "mipkg.mod:create_app@/ext/bar"  (si callable, se invoca sin args)
    """
    import os, importlib
    spec = (os.environ.get("EXT_APPS") or "").strip()
    if not spec:
        return app
    mounts = []
    for raw in [s.strip() for s in spec.split(",") if s.strip()]:
        if "@/" not in raw:  # validación mínima
            continue
        left, prefix = raw.split("@", 1)
        mod, _, attr = left.partition(":")
        try:
            m = importlib.import_module(mod)
            target = getattr(m, attr or "app", None)
            if callable(target):
                try:
                    # si es factoría devuelve la app; si es ya una app, dejar tal cual
                    import inspect
                    if inspect.signature(target).parameters:
                        ext = target  # requiere args → asumimos ya es WSGI
                    else:
                        maybe = target()
                        ext = maybe if callable(maybe) else target
                except Exception:
                    ext = target
            else:
                raise RuntimeError("objeto no callable")
            mounts.append((prefix, ext))
        except Exception:
            # ignorar entradas inválidas
            pass

    if not mounts:
        return app

    def _router(environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        for pref, ext in mounts:
            if path.startswith(pref):
                return ext(environ, start_response)
        return app(environ, start_response)
    return _router
'''

# Inyecta función y aplica el hook al final del entrypoint
ins_pos = src.rfind("\n# --- WSGI entrypoint")
if ins_pos == -1: ins_pos = len(src)
src2 = src[:ins_pos] + "\n" + BLOCK.strip() + "\n" + src[ins_pos:]

# Hook tras _root_force_mw(app)
if "app = _compose_with_ext(app)" not in src2:
    src2 = re.sub(
        r'(?m)^(?P<i>\s*)try:\s*\n(?P=i)\s*app\s*=\s*_root_force_mw\(app\).*\n(?P=i)\s*except Exception:\s*\n(?P=i)\s*pass',
        r'\g<i>try:\n\g<i>    app = _root_force_mw(app)\n\g<i>except Exception:\n\g<i>    pass\n\g<i>try:\n\g<i>    app = _compose_with_ext(app)\n\g<i>except Exception:\n\g<i>    pass',
        src2, count=1
    )

bak = W.with_suffix(".py.enable_ext_mounts.bak")
if not bak.exists(): shutil.copyfile(W, bak)
W.write_text(src2, encoding="utf-8")
py_compile.compile(str(W), doraise=True)
print(f"patched: ext mounts habilitados | backup={bak.name}")
