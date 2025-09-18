#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe", W); sys.exit(2)

def R(): return W.read_text(encoding="utf-8", errors="ignore")
def WRT(s): W.write_text(s, encoding="utf-8")
def gate():
    try:
        py_compile.compile(str(W), doraise=True); print("✓ py_compile OK"); return True
    except Exception as e:
        print("✗ py_compile FAIL:", e)
        tb = traceback.format_exc()
        m = re.search(r'__init__\.py, line (\d+)', tb)
        if m:
            ln = int(m.group(1)); ctx = R().splitlines()
            a = max(1, ln-30); b = min(len(ctx), ln+30)
            print(f"\n--- Contexto {a}-{b} ---")
            for k in range(a, b+1):
                print(f"{k:5d}: {ctx[k-1]}")
        return False

src = R().replace("\r\n","\n").replace("\r","\n").replace("\t","    ")
bak = W.with_suffix(".py.backend_v4.bak")
if not bak.exists():
    shutil.copyfile(W, bak)

# 0) helper _inject_single_attr a nivel módulo (si falta)
if "_inject_single_attr(" not in src:
    helper = (
        "\n\ndef _inject_single_attr(body, nid):\n"
        "    try:\n"
        "        b = body if isinstance(body, (bytes, bytearray)) else (body or b\"\")\n"
        "        if b:\n"
        "            return b.replace(b\"<body\", f'<body data-single=\"1\" data-note-id=\"{nid}\"'.encode(\"utf-8\"), 1)\n"
        "    except Exception:\n"
        "        pass\n"
        "    return body\n"
    )
    # insert tras _finish o al final
    mfin = re.search(r'(?m)^def[ ]+_finish\(', src)
    if mfin:
        ins = src.find("\n", mfin.end())+1
        src = src[:ins] + helper + src[ins:]
    else:
        src = src + helper

# 1) localizar def _app(...) y su indent base
m_app = re.search(r'(?m)^([ ]*)def[ ]+_app\s*\(\s*environ\s*,\s*start_response\s*\)\s*:\s*$', src)
if not m_app:
    print("✗ no encontré def _app(environ, start_response)"); sys.exit(1)
app_ws = m_app.group(1)
app_base = len(app_ws)
lines = src.split("\n")
app_hdr_idx = src[:m_app.start()].count("\n")

# descubrir indent de cuerpo (línea path/method)
body_ws = None
for i in range(app_hdr_idx+1, min(len(lines), app_hdr_idx+300)):
    L = lines[i]
    if re.match(rf'^{re.escape(app_ws)}[ ]{4}(path|method)\s*=', L or ""):
        body_ws = L[:len(L)-len(L.lstrip(" "))]
        break
if body_ws is None:
    body_ws = app_ws + "    "  # fallback
body_base = len(body_ws)

# 2) normalizar indent de bloques terms/privacy/health y return _finish cercanos
def norm_block(start_pat):
    changed = 0
    pat = re.compile(rf'^[ ]*if[ ]+path[ ]*==[ ]*"{start_pat}"[ ]*and[ ]*method[ ]*in[ ]*\("GET","HEAD"\)\s*:\s*$', re.M)
    for m in list(pat.finditer("\n".join(lines))):
        i = "\n".join(lines)[:m.start()].count("\n")
        # fuerza indent del 'if'
        if not lines[i].startswith(body_ws):
            lines[i] = body_ws + lines[i].lstrip(); changed += 1
        # status/headers/body siguiente
        if i+1 < len(lines) and "status, headers, body" in lines[i+1]:
            cur = lines[i+1].lstrip(); good = body_ws + "    " + cur
            if lines[i+1] != good: lines[i+1] = good; changed += 1
        # return _finish siguiente
        if i+2 < len(lines) and "return _finish" in lines[i+2]:
            cur = lines[i+2].lstrip(); good = body_ws + "    " + cur
            if lines[i+2] != good: lines[i+2] = good; changed += 1
    return changed

total = 0
for key in ("terms", "privacy"):
    total += norm_block(key)
# health puede estar como == "/api/health"
def norm_health():
    changed=0
    pat = re.compile(r'^[ ]*if[ ]+path[ ]*==[ ]*"/api/health"[ ]*and[ ]*method[ ]*in[ ]*\("GET","HEAD"\)\s*:\s*$', re.M)
    for m in list(pat.finditer("\n".join(lines))):
        i = "\n".join(lines)[:m.start()].count("\n")
        if not lines[i].startswith(body_ws):
            lines[i] = body_ws + lines[i].lstrip(); changed += 1
        if i+1 < len(lines) and "status, headers, body" in lines[i+1]:
            cur = lines[i+1].lstrip(); good = body_ws + "    " + cur
            if lines[i+1] != good: lines[i+1] = good; changed += 1
        if i+2 < len(lines) and "return _finish" in lines[i+2]:
            cur = lines[i+2].lstrip(); good = body_ws + "    " + cur
            if lines[i+2] != good: lines[i+2] = good; changed += 1
    return changed
total += norm_health()

# 3) inyección single-flag justo tras _serve_index_html()
src2 = "\n".join(lines)
pat_idx = re.compile(
    r'(?m)^([ ]*)if[ ]+path[ ]+in[ ]*\(\s*"/"\s*,\s*"/index\.html"\s*\)[ ]+and[ ]+method[ ]+in[ ]*\(\s*"GET","HEAD"\s*\)\s*:\s*$'
)
m0 = pat_idx.search(src2)
if m0:
    idx_hdr = src2[:m0.start()].count("\n")
    # buscar dentro del bloque hasta encontrar la línea de _serve_index_html()
    j = idx_hdr + 1
    while j < len(lines):
        L = lines[j]
        ind = len(L) - len(L.lstrip(" "))
        if L.strip() and ind <= (len(m0.group(1))):  # dedent => fin bloque
            break
        if "status, headers, body" in L and "_serve_index_html(" in L:
            inj_ws = L[:len(L)-len(L.lstrip(" "))]  # mismo indent que la línea
            inj = [
                inj_ws + "# P12: single-note flag si viene ?id= o ?note=",
                inj_ws + "try:",
                inj_ws + "    from urllib.parse import parse_qs as _pq",
                inj_ws + "    _q = _pq(qs, keep_blank_values=True) if qs else {}",
                inj_ws + "    _idv = _q.get('id') or _q.get('note')",
                inj_ws + "    if _idv and (_idv[0] or '').isdigit():",
                inj_ws + "        body = _inject_single_attr(body, _idv[0])",
                inj_ws + "except Exception:",
                inj_ws + "    pass",
            ]
            # inserta solo si no existe ya
            blk = "\n".join(lines[j+1:j+12])
            if "single-note flag" not in blk and "_inject_single_attr(" not in blk:
                lines[j+1:j+1] = inj
            break
        j += 1

out = "\n".join(lines)
if out != src:
    WRT(out)
    print(f"patched: backend rutas+single | backup={bak.name}")
else:
    print("OK: backend ya estaba normalizado")

if not gate(): sys.exit(1)
