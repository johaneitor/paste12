#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)

src = W.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n").replace("\r","\n").replace("\t", "    ")
bak = W.with_suffix(".finish_hotfix.bak")
if not bak.exists():
    shutil.copyfile(W, bak)

def canon(indent=""):
    return (
f"""{indent}def _finish(start_response, status, headers, body, method, extra_headers=None):
{indent}    try:
{indent}        # Normaliza el cuerpo a bytes y respeta HEAD
{indent}        if isinstance(body, str):
{indent}            body_bytes = body.encode("utf-8")
{indent}        elif isinstance(body, (bytes, bytearray)):
{indent}            body_bytes = bytes(body)
{indent}        else:
{indent}            body_bytes = b""
{indent}        if (method or "").upper() == "HEAD":
{indent}            body_bytes = b""
{indent}
{indent}        # Unifica headers + extra y asegura Content-Length
{indent}        hdrs = list(headers or [])
{indent}        if extra_headers:
{indent}            hdrs.extend(list(extra_headers))
{indent}        has_cl = any(k.lower() == "content-length" for k, _ in hdrs)
{indent}        if not has_cl:
{indent}            hdrs.append(("Content-Length", str(len(body_bytes))))
{indent}
{indent}        start_response(status, hdrs)
{indent}        return [body_bytes]
{indent}    except Exception:
{indent}        try:
{indent}            start_response("500 Internal Server Error", [("Content-Type","text/plain; charset=utf-8")])
{indent}        except Exception:
{indent}            pass
{indent}        return [b"internal error"]
"""
    )

changed = False

# ¿Hay def _finish? Si sí, reescribimos completo con el indent detectado
m = re.search(r'(?ms)^([ ]*)def[ ]+_finish\s*\(\s*start_response\s*,\s*status\s*,\s*headers\s*,\s*body\s*,\s*method\s*,\s*extra_headers\s*=\s*None\s*\)\s*:\s*(?:\n(?:(?:\1[ ]+).*\n)*)?', src)
if m:
    indent = m.group(1)
    src = src[:m.start()] + canon(indent) + src[m.end():]
    changed = True
else:
    # También cubrimos la firma sin extra_headers por compat
    m2 = re.search(r'(?ms)^([ ]*)def[ ]+_finish\s*\(\s*start_response\s*,\s*status\s*,\s*headers\s*,\s*body\s*,\s*method\s*\)\s*:\s*(?:\n(?:(?:\1[ ]+).*\n)*)?', src)
    if m2:
        indent = m2.group(1)
        src = src[:m2.start()] + canon(indent) + src[m2.end():]
        changed = True
    else:
        # Insertar al principio del módulo si no existe
        src = canon("") + src
        changed = True

if changed:
    W.write_text(src, encoding="utf-8")

# Gate de compilación con contexto si falla
try:
    py_compile.compile(str(W), doraise=True)
    print("✓ _finish canónico OK | backup=", bak.name)
except Exception as e:
    print("✗ py_compile FAIL:", e)
    tb = traceback.format_exc()
    mline = re.search(r'__init__\.py, line (\d+)', tb)
    if mline:
        ln = int(mline.group(1))
        ctx = src.splitlines()
        a = max(1, ln-20); b = min(len(ctx), ln+20)
        print(f"\n--- Contexto {a}-{b} ---")
        for i in range(a, b+1):
            print(f"{i:5d}: {ctx[i-1]}")
    sys.exit(1)
