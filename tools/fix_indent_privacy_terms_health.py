#!/usr/bin/env python3
import re, sys, pathlib, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)

def R(): return W.read_text(encoding="utf-8", errors="ignore")
def WRT(s): W.write_text(s, encoding="utf-8")

src = R().replace("\r\n","\n").replace("\r","\n").replace("\t","    ")
lines = src.split("\n")

# 1) localizar def _app(...)
m_app = re.search(r'(?m)^([ ]*)def[ ]+_app\s*\(\s*environ\s*,\s*start_response\s*\)\s*:\s*$', src)
if not m_app:
    print("✗ no encontré 'def _app(environ, start_response):'"); sys.exit(1)
app_ws = m_app.group(1)
app_hdr_idx = src[:m_app.start()].count("\n")

# 2) fin de bloque _app por dedent (indent <= len(app_ws))
j = app_hdr_idx + 1
end_idx = len(lines)
while j < len(lines):
    L = lines[j]
    if L.strip() and (len(L) - len(L.lstrip(" "))) <= len(app_ws):
        end_idx = j; break
    j += 1

# 3) detectar indent "normal" del cuerpo de _app (tomamos la línea 'path =' o 'method =')
body_ws = None
for k in range(app_hdr_idx+1, end_idx):
    L = lines[k]
    if re.match(r'^[ ]*#', L) or not L.strip(): continue
    m = re.match(r'^([ ]*)path\s*=\s*environ\.get\(', L)
    if not m: m = re.match(r'^([ ]*)method\s*=\s*environ\.get\(', L)
    if m: body_ws = m.group(1); break
if body_ws is None: body_ws = app_ws + "    "  # fallback: +4

targets = [
    r'^([ ]*)if\s+path\s*==\s*"/privacy"\s*and\s*method\s*in\s*\("GET","HEAD"\)\s*:\s*$',
    r'^([ ]*)if\s+path\s*==\s*"/terms"\s*and\s*method\s*in\s*\("GET","HEAD"\)\s*:\s*$',
    r'^([ ]*)if\s+path\s*==\s*"/api/health"\s*and\s*method\s*in\s*\("GET","HEAD"\)\s*:\s*$',
]
changed = 0
for k in range(app_hdr_idx+1, end_idx):
    L = lines[k]
    for pat in targets:
        if re.match(pat, L):
            cur_ws = re.match(r'^([ ]*)', L).group(1)
            if cur_ws != body_ws:
                lines[k] = body_ws + L[len(cur_ws):]
                changed += 1
            break

out = "\n".join(lines)
if out != src:
    WRT(out)
    print(f"patched: indent normalizado en {changed} línea(s)")
else:
    print("OK: indent ya consistente (sin cambios)")

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
        ctx = R().splitlines()
        a = max(1, ln-20); b = min(len(ctx), ln+20)
        print(f"\n--- Contexto {a}-{b} ---")
        for i in range(a, b+1):
            print(f"{i:5d}: {ctx[i-1]}")
    sys.exit(1)
