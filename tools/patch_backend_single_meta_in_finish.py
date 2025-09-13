#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile

W = pathlib.Path("wsgiapp/__init__.py")
src = W.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n").replace("\r","\n")

bak = W.with_suffix(".singlemeta_finish.bak")
if not bak.exists():
    shutil.copyfile(W, bak)

changed = False

# Helper idempotente: solo inyecta meta si ve data-single="1" y falta el meta
if "_inject_single_meta(" not in src:
    helper = '''
def _inject_single_meta(body):
    try:
        b = body if isinstance(body, (bytes, bytearray)) else (body or b"")
        if b and (b.find(b'data-single="1"') != -1) and (b.find(b'name="p12-single"') == -1):
            return b.replace(b"<head", b"<head><meta name=\\"p12-single\\" content=\\"1\\">", 1)
    except Exception:
        pass
    return body
'''
    # Insertar tras _finish si existe, sino al final del archivo
    m_after = re.search(r'(?m)^def[ ]+_finish\s*\([^)]*\)\s*:\s*$', src)
    insert_at = src.find("\n", m_after.end())+1 if m_after else len(src)
    src = src[:insert_at] + helper + src[insert_at:]
    changed = True

# Inyección dentro de _finish al inicio del cuerpo (si no está)
m = re.search(r'(?m)^([ ]*)def[ ]+_finish\s*\([^)]*\)\s*:\s*$', src)
if not m:
    print("✗ no encontré 'def _finish(...)' — abortando sin cambios")
    sys.exit(1)

ws = m.group(1)
body_ws = ws + "    "

# Obtener rango del cuerpo de _finish para no duplicar
lines = src.split("\n")
hdr_line = src[:m.start()].count("\n")  # línea 0-based donde empieza 'def _finish'
i = hdr_line + 1

# Saltar líneas en blanco / docstring
while i < len(lines) and (lines[i].strip() == "" or re.match(r'^[ ]*[rub]*[\'"]{3}', lines[i])):
    # Si hay docstring, avanzar hasta el cierre
    if re.match(r'^[ ]*[rub]*[\'"]{3}', lines[i]):
        q = lines[i].strip()[:3]
        i += 1
        while i < len(lines) and q not in lines[i]:
            i += 1
        i += 1
        break
    i += 1

# Si ya existe una llamada _inject_single_meta(...) dentro del cuerpo, no hacemos nada
finish_body_text = "\n".join(lines[i:i+40])
if "_inject_single_meta(" not in finish_body_text:
    inject = [
        f"{body_ws}try:",
        f"{body_ws}    body = _inject_single_meta(body)",
        f"{body_ws}except Exception:",
        f"{body_ws}    pass",
    ]
    lines[i:i] = inject
    src = "\n".join(lines)
    changed = True

# Guardar + gate
if changed:
    W.write_text(src, encoding="utf-8")
try:
    py_compile.compile(str(W), doraise=True)
    print("✓ single-meta en _finish aplicado | backup=", bak.name if bak.exists() else "(none)")
except Exception as e:
    print("✗ py_compile FAIL:", e)
    if bak.exists():
        shutil.copyfile(bak, W)
    sys.exit(1)
