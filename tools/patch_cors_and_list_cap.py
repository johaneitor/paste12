#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)

def R(): return W.read_text(encoding="utf-8")
def WRT(s): W.write_text(s, encoding="utf-8")
def norm(s): return s.replace("\r\n","\n").replace("\r","\n").replace("\t","    ")

def gate():
    try:
        py_compile.compile(str(W), doraise=True)
        print("✓ py_compile OK"); return True
    except Exception as e:
        print("✗ py_compile FAIL:", e)
        tb = traceback.format_exc()
        m = re.search(r'__init__\.py, line (\d+)', tb)
        if m:
            ln = int(m.group(1)); ctx = R().splitlines()
            a = max(1, ln-35); b = min(len(ctx), ln+35)
            print(f"\n--- Ventana {a}-{b} ---")
            for k in range(a, b+1): print(f"{k:5d}: {ctx[k-1]}")
        return False

src = norm(R())
orig = src

# ---------- (A) Patch preflight CORS ----------
# Localiza def _app y el if de preflight
m_app = re.search(r'(?m)^([ ]*)def\s+_app\s*\(\s*environ\s*,\s*start_response\s*\)\s*:\s*$', src)
if not m_app:
    print("✗ no encontré 'def _app(environ, start_response):'"); sys.exit(1)
app_ws = m_app.group(1); app_base = len(app_ws)
app_start = m_app.end()
# Encuentra el bloque if method == "OPTIONS" and path.startswith("/api/"):
pat_pre = re.compile(rf'(?m)^{re.escape(app_ws)}[ ]{{4}}if\s+method\s*==\s*"OPTIONS"\s*and\s*path\.startswith\("/api/"\)\s*:\s*$')
m_pre = pat_pre.search(src, app_start)
if not m_pre:
    print("⚠ no encontré bloque preflight; no toco CORS")
else:
    # Delimitar bloque por dedent (<= app_base+4)
    lines = src.split("\n")
    idx0 = src[:m_pre.start()].count("\n")
    k = idx0 + 1
    while k < len(lines):
        L = lines[k]
        ind = len(L) - len(L.lstrip(" "))
        if L.strip() and ind <= app_base + 4:
            break
        k += 1
    # En rango [idx0, k) modificar headers
    for i in range(idx0, k):
        L = lines[i]
        # Allow-Headers → incluye Authorization
        if "Access-Control-Allow-Headers" in L:
            lines[i] = re.sub(
                r'("Access-Control-Allow-Headers",\s*")[^"]*(")',
                r'\1Content-Type, Accept, Authorization\2',
                L
            )
        # Max-Age → 1800
        if "Access-Control-Max-Age" in L:
            lines[i] = re.sub(
                r'("Access-Control-Max-Age",\s*")\d+(")',
                r'\g<1>1800\2',
                lines[i]
            )
    src = "\n".join(lines)

# ---------- (B) Cap de listado en handler GET /api/notes ----------
# Buscamos el bloque:
m_list = re.search(
    r'(?m)^([ ]*)if\s+path\s+in\s*\(\s*"/api/notes"\s*,\s*"/api/notes_fallback"\s*\)\s*and\s*method\s+in\s*\(\s*"GET"\s*,\s*"HEAD"\s*\)\s*:\s*$',
    src
)
if not m_list:
    print("⚠ no encontré handler GET /api/notes (no aplico cap en salida)")
else:
    h_ws = m_list.group(1)
    # hallamos "code, payload, nxt = _notes_query(qs)"
    pat_call = re.compile(rf'(?m)^{re.escape(h_ws)}[ ]{{4}}code,\s*payload,\s*nxt\s*=\s*_notes_query\(\s*qs\s*\)\s*$')
    m_call = pat_call.search(src, m_list.end())
    if not m_call:
        print("⚠ no hallé la llamada a _notes_query(qs)")
    else:
        # Insertamos justo después un recorte de items a MAX_LIMIT
        insert_after_idx = src[:m_call.end()].count("\n")
        lines = src.split("\n")
        IND = h_ws + "    "
        block = [
            IND + "try:",
            IND + "    import os",
            IND + "    _MAX_LIMIT = int(os.environ.get('MAX_LIMIT', '100') or '100')",
            IND + "    if isinstance(payload, dict) and isinstance(payload.get('items'), list):",
            IND + "        payload['items'] = payload['items'][:_MAX_LIMIT]",
            IND + "except Exception:",
            IND + "    pass",
            ""
        ]
        lines[insert_after_idx+1:insert_after_idx+1] = block
        src = "\n".join(lines)

if src == orig:
    print("OK: no hubo cambios")
    if not gate(): sys.exit(1)
    sys.exit(0)

bak = W.with_suffix(".py.patch_cors_and_list_cap.bak")
if not bak.exists():
    shutil.copyfile(W, bak)
WRT(src)
print(f"patched: CORS(headers/max-age) + cap listado | backup={bak.name}")

if not gate(): sys.exit(1)
