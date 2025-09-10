#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback, datetime as _dt

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)

def R(): return W.read_text(encoding="utf-8")
def norm(s: str) -> str: return s.replace("\r\n","\n").replace("\r","\n").replace("\t","    ")

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
lines = src.split("\n")

# 1) localizar 'def _app(environ, start_response):'
m_app = re.search(r'(?m)^([ ]*)def[ ]+_app\s*\(\s*environ\s*,\s*start_response\s*\)\s*:\s*$', src)
if not m_app:
    print("✗ no encontré 'def _app(environ, start_response):'"); sys.exit(1)
app_ws = m_app.group(1); app_base = len(app_ws)
app_hdr_idx = src[:m_app.start()].count("\n")

# hallar fin de _app por dedent
j = app_hdr_idx + 1; end_app = len(lines)
while j < len(lines):
    L = lines[j]
    if L.strip() and (len(L) - len(L.lstrip(" "))) <= app_base:
        end_app = j; break
    j += 1

# 2) buscar bloque actual de /api/deploy-stamp
pat_stamp = re.compile(rf'^{re.escape(app_ws)}[ ]{{4}}if\s+path\s*==\s*["\']/api/deploy-stamp["\']\s*.*$', re.M)
m_stamp = pat_stamp.search("\n".join(lines[app_hdr_idx+1:end_app]))
start_if_idx = None; if_ws = None

if m_stamp:
    start_if_idx = app_hdr_idx + 1 + ("\n".join(lines[app_hdr_idx+1:end_app])[:m_stamp.start()].count("\n"))
    if_ws = re.match(r'^([ ]*)', lines[start_if_idx]).group(1)
    if_base = len(if_ws)
    # delimitar bloque por dedent
    k = start_if_idx + 1
    while k < end_app:
        L = lines[k]
        if L.strip() and (len(L) - len(L.lstrip(" "))) <= if_base:
            break
        k += 1
    end_if_idx = k
else:
    # si no existe, insertaremos tras el bloque de /api/health
    pat_health = re.compile(rf'^{re.escape(app_ws)}[ ]{{4}}if\s+path\s*==\s*["\']/api/health["\']\s*.*$', re.M)
    m_h = pat_health.search("\n".join(lines[app_hdr_idx+1:end_app]))
    if not m_h:
        print("✗ no encontré /api/health para anclar"); sys.exit(1)
    h_start = app_hdr_idx + 1 + ("\n".join(lines[app_hdr_idx+1:end_app])[:m_h.start()].count("\n"))
    h_ws = re.match(r'^([ ]*)', lines[h_start]).group(1); h_base = len(h_ws)
    k = h_start + 1
    while k < end_app:
        L = lines[k]
        if L.strip() and (len(L) - len(L.lstrip(" "))) <= h_base:
            break
        k += 1
    start_if_idx = k  # insert AFTER /api/health block
    end_if_idx = k
    if_ws = h_ws

IND  = if_ws or (app_ws + "    ")
code = [
    IND + 'if path == "/api/deploy-stamp" and method in ("GET","HEAD"):',
    IND + '    try:',
    IND + '        import os, json  # local, por robustez en runtime',
    IND + '        commit = (os.environ.get("RENDER_GIT_COMMIT") or os.environ.get("COMMIT") or "")',
    IND + '        date   = (os.environ.get("DEPLOY_STAMP") or os.environ.get("RENDER_DEPLOY") or "")',
    IND + '        if not date:',
    IND + '            date = _dt.datetime.utcnow().replace(microsecond=0).isoformat() + "Z"',
    IND + '        # Respuesta compatible: {deploy:{commit,date}} y también {commit,date}',
    IND + '        payload = {"ok": True, "deploy": {"commit": commit, "date": date}, "commit": commit, "date": date}',
    IND + '        status, headers, body = _json(200, payload)',
    IND + '    except Exception as e:',
    IND + '        status, headers, body = _json(500, {"ok": False, "error": f"deploy_stamp: {e}"})',
    IND + '    return _finish(start_response, status, headers, body, method)',
    ""
]

if m_stamp:
    lines[start_if_idx:end_if_idx] = code
    action = "reemplazado"
else:
    lines[start_if_idx:start_if_idx] = code
    action = "insertado"

out = "\n".join(lines)
if out == src:
    print("OK: no hubo cambios (bloque ya canónico)"); sys.exit(0)

bak = W.with_suffix(".py.patch_deploy_stamp_api.bak")
if not bak.exists():
    shutil.copyfile(W, bak)
W.write_text(out, encoding="utf-8")
print(f"patched: handler /api/deploy-stamp {action} | backup={bak.name}")

if not gate(): sys.exit(1)
