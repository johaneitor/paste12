#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)

def read(): return W.read_text(encoding="utf-8", errors="ignore")
def write(s): W.write_text(s, encoding="utf-8")

src = read().replace("\r\n","\n").replace("\r","\n").replace("\t","    ")
lines = src.split("\n")

# Localiza def _app(...) (puede aparecer más de una vez; usamos la primera)
m_app = re.search(r'(?m)^([ ]*)def[ ]+_app\s*\(\s*environ\s*,\s*start_response\s*\)\s*:\s*$', src)
if not m_app:
    print("✗ no encontré 'def _app(environ, start_response):'"); sys.exit(1)

app_ws = m_app.group(1)
app_hdr_idx = src[:m_app.start()].count("\n")

# Determina indent "normal" del cuerpo (buscamos la línea 'path =' o 'method =')
body_ws = None
for k in range(app_hdr_idx+1, min(app_hdr_idx+300, len(lines))):
    L = lines[k]
    if not L.strip(): continue
    m = re.match(r'^([ ]*)path\s*=\s*environ\.get\(', L) or re.match(r'^([ ]*)method\s*=\s*environ\.get\(', L)
    if m:
        body_ws = m.group(1)
        break
if body_ws is None:
    body_ws = app_ws + "    "  # fallback a +4

def fix_simple_block(keyword: str, rhs_expr: str):
    """
    Normaliza:
      if path == "/X" and method in ("GET","HEAD"):
          status, headers, body = <rhs_expr>
          return _finish(...)
    Fuerza indent del 'if' a body_ws y de su cuerpo a body_ws + 4.
    """
    global lines
    pat_if = re.compile(r'^[ ]*if\s+path\s*==\s*"' + re.escape(keyword) + r'"\s*and\s*method\s*in\s*\("GET","HEAD"\)\s*:\s*$')
    changed = 0
    for i in range( max(app_hdr_idx+1, 0), min(app_hdr_idx+600, len(lines)) ):
        if pat_if.match(lines[i] or ""):
            # Re-indent del if
            if not lines[i].startswith(body_ws):
                lines[i] = body_ws + lines[i].lstrip()
                changed += 1
            # Cuerpo esperado (dos líneas)
            # status...
            if i+1 < len(lines) and "status, headers, body" in lines[i+1]:
                cur = lines[i+1].lstrip()
                good = (body_ws + "    " + cur)
                if lines[i+1] != good:
                    lines[i+1] = good
                    changed += 1
            # return _finish
            if i+2 < len(lines) and "return _finish" in lines[i+2]:
                cur = lines[i+2].lstrip()
                good = (body_ws + "    " + cur)
                if lines[i+2] != good:
                    lines[i+2] = good
                    changed += 1
            break
    return changed

total_changes = 0
total_changes += fix_simple_block("terms"  , '_html(200, _TERMS_HTML)')
total_changes += fix_simple_block("privacy", '_html(200, _PRIVACY_HTML)')
total_changes += fix_simple_block("api/health", '_json(200, {"ok": True})')

if total_changes == 0:
    print("OK: indent ya consistente (sin cambios)")
else:
    bak = W.with_suffix(".py.routes_indent.bak")
    if not bak.exists():
        shutil.copyfile(W, bak)
    write("\n".join(lines))
    print(f"patched: normalizados bloques (cambios={total_changes}) | backup={bak.name}")

# Gate de compilación con ventana de contexto si falla
try:
    py_compile.compile(str(W), doraise=True)
    print("✓ py_compile OK")
except Exception as e:
    print("✗ py_compile FAIL:", e)
    tb = traceback.format_exc()
    m = re.search(r'__init__\.py, line (\d+)', tb)
    if m:
        ln = int(m.group(1))
        ctx = read().splitlines()
        a = max(1, ln-25); b = min(len(ctx), ln+25)
        print(f"\n--- Contexto {a}-{b} ---")
        for i in range(a, b+1):
            print(f"{i:5d}: {ctx[i-1]}")
    sys.exit(1)
