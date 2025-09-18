#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)
src = W.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n").replace("\r","\n").replace("\t","    ")
bak = W.with_suffix(".final_singlemeta_fix.bak")
if not bak.exists():
    shutil.copyfile(W, bak)

def write(s): W.write_text(s, encoding="utf-8")

# 0) Canon del helper
HELPER = (
    "\n"
    "def _inject_single_meta(body_bytes):\n"
    "    try:\n"
    "        b = body_bytes if isinstance(body_bytes, (bytes, bytearray)) else (body_bytes or b\"\")\n"
    "        # Sólo si detectamos <body ... data-single=\"1\"> y NO existe ya la meta\n"
    "        if b and (b.find(b'data-single=\"1\"') != -1) and (b.find(b'name=\"p12-single\"') == -1):\n"
    "            return b.replace(b\"<head\", b\"<head><meta name=\\\"p12-single\\\" content=\\\"1\\\">\", 1)\n"
    "    except Exception:\n"
    "        pass\n"
    "    return body_bytes\n"
)

changed = False

# 1) Quitar bloque 'huérfano' a nivel módulo (como el de tu contexto 140–146)
#    Lo anclamos a columna 0 para no tocar el interior de funciones.
src2 = re.sub(
    r'(?ms)^try:\n\s*b\s*=\s*body[^\n]*\n\s*if\s+b[^\n]*p12-single[^\n]*\n\s*except\s+Exception\s*:\s*\n\s*pass\s*\n\s*return\s+body\s*\n?',
    '',
    src
)
if src2 != src:
    src = src2; changed = True

# 2) Eliminar TODAS las definiciones previas de _inject_single_meta (si hay varias/rotas)
def remove_all_helper_defs(s: str) -> str:
    out = []
    i = 0
    pat = re.compile(r'(?m)^def\s+_inject_single_meta\s*\([^)]*\)\s*:\s*$')
    while True:
        m = pat.search(s, i)
        if not m:
            out.append(s[i:]); break
        # copiar lo que hay antes
        out.append(s[i:m.start()])
        # saltar hasta el próximo def/class/if main a columna 0 o EOF
        j = m.end()
        nxt = re.search(r'(?m)^(def |class |if __name__ == )', s[j:])
        if nxt:
            j = j + nxt.start()
        else:
            j = len(s)
        # no agregamos ese bloque (lo eliminamos)
        i = j
    return ''.join(out)

src2 = remove_all_helper_defs(src)
if src2 != src:
    src = src2; changed = True

# 3) Insertar helper canónico tras el último import (o al inicio del módulo)
imports = list(re.finditer(r'(?m)^(?:from\s+\S+\s+import\s+\S+|import\s+\S+)', src))
ins_at = imports[-1].end() if imports else 0
ins_at = src.find("\n", ins_at) + 1 if "\n" in src[ins_at:] else len(src)
src = src[:ins_at] + HELPER + src[ins_at:]
changed = True

# 4) Inyectar llamada dentro de _finish() (idempotente) después de 'body_bytes = ...'
m = re.search(r'(?m)^([ ]*)def[ ]+_finish\s*\([^)]*\)\s*:\s*$', src)
if not m:
    print("✗ no encontré 'def _finish(...)' — no aplico inyección en _finish")
else:
    fn_ws = m.group(1)
    lines = src.split("\n")
    def_line = src[:m.start()].count("\n")  # 0-based
    # hallar indent del cuerpo
    body_ws = None
    for j in range(def_line+1, min(def_line+100, len(lines))):
        if lines[j].strip():
            mm = re.match(r'^([ ]+)\S', lines[j])
            if mm: body_ws = mm.group(1)
            break
    if body_ws is None:
        body_ws = fn_ws + "    "

    # localizar 'body_bytes ='
    start = def_line+1
    target_idx = None
    for j in range(start, min(def_line+200, len(lines))):
        if re.match(r'^[ ]*body_bytes\s*=', lines[j]):
            target_idx = j
            break

    # eliminar inyección previa igual a la que pondremos
    inj_try = [
        f"{body_ws}try:",
        f"{body_ws}    body_bytes = _inject_single_meta(body_bytes)",
        f"{body_ws}except Exception:",
        f"{body_ws}    pass",
    ]
    inj_block = "\n".join(inj_try)
    txt = "\n".join(lines)
    txt2 = txt.replace("\n"+inj_block+"\n", "\n")
    if txt2 != txt:
        src = txt2; lines = src.split("\n"); changed = True
        # recomputar indices si cambió
        m = re.search(r'(?m)^([ ]*)def[ ]+_finish\s*\([^)]*\)\s*:\s*$', src)
        def_line = src[:m.start()].count("\n")
        lines = src.split("\n")

        # localizar otra vez 'body_bytes ='
        target_idx = None
        for j in range(def_line+1, min(def_line+200, len(lines))):
            if re.match(r'^[ ]*body_bytes\s*=', lines[j]):
                target_idx = j; break

    if target_idx is not None:
        # insertar inmediatamente después
        ins_pos = target_idx + 1
        lines[ins_pos:ins_pos] = inj_try
        src = "\n".join(lines)
        changed = True
    else:
        # fallback: insertar al inicio del cuerpo
        ins_pos = def_line + 1
        lines[ins_pos:ins_pos] = inj_try
        src = "\n".join(lines)
        changed = True

# 5) Escribir y compilar; mostrar contexto si falla
if changed:
    write(src)

try:
    py_compile.compile(str(W), doraise=True)
    print("✓ saneado: helper único + inyección en _finish | backup=", bak.name)
except Exception as e:
    print("✗ py_compile FAIL:", e)
    tb = traceback.format_exc()
    mm = re.search(r'__init__\.py, line (\d+)', tb)
    if mm:
        ln = int(mm.group(1))
        ctx = W.read_text(encoding="utf-8", errors="ignore").splitlines()
        a = max(1, ln-30); b = min(len(ctx), ln+30)
        print(f"\n--- Contexto {a}-{b} ---")
        for k in range(a, b+1):
            print(f"{k:5d}: {ctx[k-1]}")
    print("\nRestaurando backup…")
    shutil.copyfile(bak, W)
    sys.exit(1)
