#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)

def R(): return W.read_text(encoding="utf-8", errors="ignore")
def WRT(s): W.write_text(s, encoding="utf-8")

src = R().replace("\r\n","\n").replace("\r","\n").replace("\t","    ")

bak = W.with_suffix(".finish_singlemeta_fix.bak")
if not bak.exists():
    shutil.copyfile(W, bak)

changed = False

# ---------- 1) Asegurar helper a nivel módulo (idempotente)
if "_inject_single_meta(" not in src:
    helper = (
        "\n"
        "def _inject_single_meta(body):\n"
        "    try:\n"
        "        b = body if isinstance(body, (bytes, bytearray)) else (body or b\"\")\n"
        "        if b and (b.find(b'data-single=\"1\"') != -1) and (b.find(b'name=\"p12-single\"') == -1):\n"
        "            return b.replace(b\"<head\", b\"<head><meta name=\\\"p12-single\\\" content=\\\"1\\\">\", 1)\n"
        "    except Exception:\n"
        "        pass\n"
        "    return body\n"
    )
    # Insertar tras el último import si existe, sino al final
    m_imports = list(re.finditer(r'(?m)^(?:from\s+\S+\s+import\s+\S+|import\s+\S+)', src))
    insert_at = m_imports[-1].end() if m_imports else len(src)
    # Avanzar hasta el fin de línea
    insert_at = src.find("\n", insert_at) + 1 if "\n" in src[insert_at:] else len(src)
    src = src[:insert_at] + helper + src[insert_at:]
    changed = True

# ---------- 2) Localizar def _finish
m = re.search(r'(?m)^([ ]*)def[ ]+_finish\s*\([^)]*\)\s*:\s*$', src)
if not m:
    print("✗ no encontré 'def _finish(...)' — no toco nada"); sys.exit(1)

fn_ws = m.group(1)
lines = src.split("\n")
hdr_line = src[:m.start()].count("\n")  # 0-based index de la línea del def
i = hdr_line + 1

# Saltar líneas vacías / docstring
while i < len(lines) and (lines[i].strip() == "" or re.match(r'^[ ]*[rub]*[\'\"]{3}', lines[i].strip())):
    if re.match(r'^[ ]*[rub]*[\'\"]{3}', lines[i].strip()):
        q = lines[i].strip()[:3]
        i += 1
        while i < len(lines) and q not in lines[i]:
            i += 1
        i += 1
        break
    i += 1

# Calcular indent del cuerpo
body_ws = None
for j in range(i, min(i+80, len(lines))):
    if lines[j].strip():
        m2 = re.match(r'^([ ]+)\S', lines[j])
        if m2:
            body_ws = m2.group(1)
        break
if body_ws is None:
    body_ws = fn_ws + "    "  # fallback

# ---------- 3) Limpiar inyecciones previas mal indentadas
# Quitar cualquier bloque try: body=_inject_single_meta(...) except: pass al inicio del cuerpo
j = i
removed = False
pat_try = re.compile(r'^' + re.escape(body_ws) + r'try:\s*$')
pat_call = re.compile(r'^\s*body\s*=\s*_inject_single_meta\(body\)\s*$')
pat_exc = re.compile(r'^' + re.escape(body_ws) + r'except\s+Exception\s*:\s*$')
pat_pass = re.compile(r'^' + re.escape(body_ws) + r'    pass\s*$')

if j < len(lines) and pat_try.match(lines[j] or ""):
    # revisar estructura esperada de 4 líneas
    blk = lines[j:j+4]
    if len(blk) >= 4 and pat_call.match(blk[1] or "") and pat_exc.match(blk[2] or "") and pat_pass.match(blk[3] or ""):
        del lines[j:j+4]
        removed = True

# Si había un try mal indentado con mismo contenido, eliminar variantes comunes
for look in range(i, min(i+10, len(lines))):
    if "_inject_single_meta(" in lines[look]:
        # Buscar hacia atrás hasta "try:" y eliminar hasta "pass"
        a = look
        while a > i and "try" not in lines[a]:
            a -= 1
        b = look
        while b < len(lines) and "pass" not in lines[b]:
            b += 1
        if a >= i and b < len(lines):
            del lines[a:b+1]
            removed = True
            break

if removed:
    changed = True

# ---------- 4) Inyectar bloque correcto
inject = [
    f"{body_ws}try:",
    f"{body_ws}    body = _inject_single_meta(body)",
    f"{body_ws}except Exception:",
    f"{body_ws}    pass",
]
lines[i:i] = inject
src2 = "\n".join(lines)

# ---------- 5) Guardar + compilar con contexto en error
if changed or src2 != R():
    WRT(src2)

try:
    py_compile.compile(str(W), doraise=True)
    print("✓ _finish normalizado + single-meta OK | backup=", bak.name)
except Exception as e:
    print("✗ py_compile FAIL:", e)
    tb = traceback.format_exc()
    mline = re.search(r'__init__\.py, line (\d+)', tb)
    if mline:
        ln = int(mline.group(1))
        ctx = R().splitlines()
        a = max(1, ln-30); b = min(len(ctx), ln+30)
        print(f"\n--- Contexto {a}-{b} ---")
        for k in range(a, b+1):
            print(f"{k:5d}: {ctx[k-1]}")
    print("\nRestaurando backup…")
    shutil.copyfile(bak, W)
    sys.exit(1)
