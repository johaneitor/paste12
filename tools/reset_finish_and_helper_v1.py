#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)

src = W.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n").replace("\r","\n").replace("\t","    ")

bak = W.with_suffix(".reset_finish_helper.bak")
if not bak.exists():
    shutil.copyfile(W, bak)

def write(s: str): W.write_text(s, encoding="utf-8")

changed = False

# --- 1) Quitar cualquier bloque try "huérfano" a nivel módulo (sin except/finally) ---
# Buscamos: ^try:\n(...hasta antes de próximo def/class/if a columna 0 o EOF) que NO tenga ^except o ^finally
def remove_orphan_try_blocks(s: str) -> str:
    out = []
    i = 0
    pat = re.compile(r'(?m)^try:\n')
    while True:
        m = pat.search(s, i)
        if not m:
            out.append(s[i:]); break
        # Copiamos hasta el 'try:'
        out.append(s[i:m.start()])
        # Fin de bloque: antes del próximo def/class/if/try/except/finally a columna 0 o EOF
        j = m.end()
        nxt = re.search(r'(?m)^(def |class |if __name__|try:|except\b|finally\b|#)', s[j:])
        end = j + (nxt.start() if nxt else len(s[j:]))
        chunk = s[m.start():end]
        # ¿Contiene except/finally a columna 0 dentro del mismo fragmento?
        has_exc = re.search(r'(?m)^except\b', chunk) or re.search(r'(?m)^finally\b', chunk)
        if has_exc:
            # Dejar tal cual si está completo
            out.append(chunk)
        else:
            # Remover bloque huérfano completo
            # (no añadimos chunk)
            pass
        i = end
    return ''.join(out)

src2 = remove_orphan_try_blocks(src)
if src2 != src:
    src = src2; changed = True

# --- 2) Quitar helper(es) previos de _inject_single_meta ---
def remove_all_helper_defs(s: str) -> str:
    out = []
    i = 0
    pat = re.compile(r'(?m)^def\s+_inject_single_meta\s*\([^)]*\)\s*:\s*$')
    while True:
        m = pat.search(s, i)
        if not m:
            out.append(s[i:]); break
        out.append(s[i:m.start()])
        j = m.end()
        # saltar hasta próximo def/class/if __name__ ... o EOF
        nxt = re.search(r'(?m)^(def |class |if __name__\s*==)', s[j:])
        j = j + (nxt.start() if nxt else len(s[j:]))
        i = j
    return ''.join(out)

src2 = remove_all_helper_defs(src)
if src2 != src:
    src = src2; changed = True

# --- 3) Insertar helper canónico tras el último import o al inicio ---
HELPER = (
    "\n"
    "def _inject_single_meta(body_bytes):\n"
    "    try:\n"
    "        b = body_bytes if isinstance(body_bytes, (bytes, bytearray)) else (body_bytes or b\"\")\n"
    "        if not b:\n"
    "            return body_bytes\n"
    "        if (b.find(b'data-single=\"1\"') != -1) and (b.find(b'name=\"p12-single\"') == -1):\n"
    "            return b.replace(b\"<head\", b\"<head><meta name=\\\"p12-single\\\" content=\\\"1\\\">\", 1)\n"
    "    except Exception:\n"
    "        pass\n"
    "    return body_bytes\n"
)

imports = list(re.finditer(r'(?m)^(?:from\s+\S+\s+import\s+\S+|import\s+\S+)', src))
ins_at = imports[-1].end() if imports else 0
ins_at = src.find("\n", ins_at) + 1 if "\n" in src[ins_at:] else len(src)
src = src[:ins_at] + HELPER + src[ins_at:]
changed = True

# --- 4) Reescribir cuerpo de _finish por uno estable ---
FINISH_HEAD = re.compile(r'(?m)^([ ]*)def[ ]+_finish\s*\([^)]*\)\s*:\s*$')
m = FINISH_HEAD.search(src)
if not m:
    print("✗ no encontré 'def _finish(...)' en el módulo"); sys.exit(1)

fn_ws = m.group(1)
lines = src.split("\n")
def_line = src[:m.start()].count("\n")  # 0-based

# Encontrar comienzo del cuerpo (primera línea no vacía con indent mayor)
body_start = None
for j in range(def_line+1, len(lines)):
    if lines[j].strip():
        mm = re.match(r'^([ ]+)\S', lines[j])
        if mm: body_start = j; break
if body_start is None:
    # si no hay cuerpo, lo creamos en def_line+1
    body_start = def_line+1

# Encontrar final del cuerpo hasta el próximo def/class a columna 0 o EOF
end = len(lines)
for j in range(body_start, len(lines)):
    if re.match(r'^(def |class )', lines[j]):
        end = j; break

# Cuerpo canónico (4 espacios de indent sobre fn_ws)
i1 = fn_ws + "    "
finish_body = [
    f"{i1}try:",
    f"{i1}    # Normaliza body a bytes",
    f"{i1}    if isinstance(body, (bytes, bytearray)):",
    f"{i1}        body_bytes = bytes(body)",
    f"{i1}    elif body is None:",
    f"{i1}        body_bytes = b\"\"",
    f"{i1}    elif isinstance(body, list):",
    f"{i1}        body_bytes = b\"\".join(x if isinstance(x,(bytes,bytearray)) else str(x).encode(\"utf-8\") for x in body)",
    f"{i1}    elif isinstance(body, str):",
    f"{i1}        body_bytes = body.encode(\"utf-8\")",
    f"{i1}    else:",
    f"{i1}        try:",
    f"{i1}            body_bytes = bytes(body)",
    f"{i1}        except Exception:",
    f"{i1}            body_bytes = str(body).encode(\"utf-8\")",
    "",
    f"{i1}    # Inyecta meta p12-single si detecta body data-single",
    f"{i1}    try:",
    f"{i1}        body_bytes = _inject_single_meta(body_bytes)",
    f"{i1}    except Exception:",
    f"{i1}        pass",
    "",
    f"{i1}    # Unifica headers + extra y asegura Content-Length",
    f"{i1}    hdrs = list(headers or [])",
    f"{i1}    if extra_headers:",
    f"{i1}        hdrs.extend(list(extra_headers))",
    f"{i1}    if not any((k.lower() == \"content-length\") for k,_ in hdrs):",
    f"{i1}        hdrs.append((\"Content-Length\", str(len(body_bytes))))",
    f"{i1}    has_ct = None",
    f"{i1}    for k,v in hdrs:",
    f"{i1}        if k.lower() == \"content-type\":",
    f"{i1}            has_ct = v; break",
    f"{i1}    if has_ct is None and (body_bytes.startswith(b\"<!doctype html\") or b\"<html\" in body_bytes[:200]):",
    f"{i1}        hdrs.append((\"Content-Type\",\"text/html; charset=utf-8\"))",
    "",
    f"{i1}    start_response(status, hdrs)",
    f"{i1}    return [body_bytes]",
    f"{i1}except Exception:",
    f"{i1}    try:",
    f"{i1}        start_response(\"500 Internal Server Error\", [(\"Content-Type\",\"text/plain; charset=utf-8\")])",
    f"{i1}    except Exception:",
    f"{i1}        pass",
    f"{i1}    return [b\"internal error\"]",
]

new_lines = lines[:def_line+1] + finish_body + lines[end:]
src = "\n".join(new_lines)
changed = True

# --- 5) Guardar y compilar; contexto si falla ---
if changed:
    write(src)

try:
    py_compile.compile(str(W), doraise=True)
    print("✓ saneado: _finish reescrito + helper único | backup=", bak.name)
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
