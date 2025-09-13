#!/usr/bin/env python3
import re, pathlib, shutil, sys, py_compile

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)

src = W.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n").replace("\r","\n")
src = src.replace("\t","    ")

bak = W.with_suffix(".single_meta_hotfix.bak")
if not bak.exists():
    shutil.copyfile(W, bak)

def _canon(indent=""):
    return (
        f"{indent}def _inject_single_meta(body):\n"
        f"{indent}    try:\n"
        f"{indent}        b = body if isinstance(body,(bytes,bytearray)) else (body or b\"\")\n"
        f"{indent}        if b and b\"<meta name=\\\"p12-single\\\"\" not in b:\n"
        f"{indent}            return b.replace(b\"<head\", b\"<head><meta name=\\\"p12-single\\\" content=\\\"1\\\">\", 1)\n"
        f"{indent}    except Exception:\n"
        f"{indent}        pass\n"
        f"{indent}    return body\n"
    )

changed = False

# 1) Normalizar/crear el helper con cuerpo válido
m = re.search(r'(?ms)^(?P<i>[ ]*)def[ ]+_inject_single_meta\s*\(\s*body\s*\)\s*:\s*\n(?P<body>(?:\1[ ]+.*\n)*)', src)
if m:
    # Reemplazar por la versión canónica (aunque ya exista, para matar indent “raro”)
    i = m.group('i')
    src = src[:m.start()] + _canon(i) + src[m.end():]
    changed = True
else:
    # Existe def sin cuerpo?
    m2 = re.search(r'(?m)^(?P<i>[ ]*)def[ ]+_inject_single_meta\s*\(\s*body\s*\)\s*:\s*$', src)
    if m2:
        i = m2.group('i')
        ins_at = m2.end()
        src = src[:ins_at] + "\n" + _canon(i) + src[ins_at:]
        changed = True
    else:
        # No existe: insertar tras _finish si está, o al inicio del módulo
        m3 = re.search(r'(?m)^def[ ]+_finish\(', src)
        ins_at = src.find("\n", m3.end())+1 if m3 else 0
        src = src[:ins_at] + _canon("") + ("\n" if not src.endswith("\n") else "") + src[ins_at:]
        changed = True

# 2) Asegurar la llamada en el bloque de /?id=NNN (donde ya se hace body=_b)
if not re.search(r'(?m)^[ ]*body[ ]*=[ ]*_inject_single_meta\(body\)', src):
    # Buscamos la asignación “body = _b” del bloque de inyección data-single
    pat_body_b = re.compile(r'(?m)^([ ]*)body[ ]*=[ ]*_b[ ]*$')
    def _add_after(mb):
        indent = mb.group(1) or ""
        return mb.group(0) + "\n" + f"{indent}body = _inject_single_meta(body)"
    src2, n = pat_body_b.subn(_add_after, src, count=1)
    if n > 0:
        src = src2
        changed = True
    # Si no encontramos “body = _b”, intentamos colgar tras la línea donde se hace el replace de <body
    if n == 0:
        pat_replace = re.compile(r'(?m)^([ ]*)_b[ ]*=[ ]*_b\.replace\([^\\n]+data-single', re.IGNORECASE)
        def _add_after2(mr):
            # Insertar dos líneas después para no romper el bloque try/except
            line_start = mr.end()
            # Encontrar la siguiente línea “body = _b” si existe tras el replace
            return mr.group(0)
        # Si tampoco está, no forzamos nada más (la página ya funciona por data-single)

# Guardar si hubo cambios
if changed:
    W.write_text(src, encoding="utf-8")

# 3) Gate de compilación
try:
    py_compile.compile(str(W), doraise=True)
    print("✓ hotfix aplicado y compiló OK | backup=", bak.name)
except Exception as e:
    print("✗ aún falla compilación:", e)
    import traceback
    tb = traceback.format_exc()
    mm = re.search(r'__init__\.py, line (\d+)', tb)
    if mm:
        ln = int(mm.group(1))
        ctx = src.splitlines()
        a = max(1, ln-20); b = min(len(ctx), ln+20)
        print(f"\n--- Contexto {a}-{b} ---")
        for k in range(a, b+1):
            print(f"{k:5d}: {ctx[k-1]}")
    sys.exit(1)
