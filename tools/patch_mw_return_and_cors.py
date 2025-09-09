#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)

def norm(s:str)->str:
    s = s.replace("\r\n","\n").replace("\r","\n")
    return s.replace("\t","    ")

def gate():
    try:
        py_compile.compile(str(W), doraise=True)
        print("✓ py_compile OK"); return True
    except Exception as e:
        print("✗ py_compile FAIL:", e)
        tb = traceback.format_exc()
        m = re.search(r'__init__\.py, line (\d+)', tb)
        if m:
            ln = int(m.group(1))
            ctx = W.read_text(encoding="utf-8").splitlines()
            a = max(1, ln-35); b = min(len(ctx), ln+35)
            print(f"\n--- Ventana {a}-{b} ---")
            for k in range(a, b+1):
                print(f"{k:5d}: {ctx[k-1]}")
        return False

src = norm(W.read_text(encoding="utf-8"))
lines = src.split("\n")

# ===== 1) localizar def _middleware =====
m = re.search(r'(?m)^([ ]*)def[ ]+_middleware\([^)]*\)\s*:\s*$', src)
if not m:
    print("✗ no encontré 'def _middleware(...)'"); sys.exit(1)

base_ws = m.group(1)
base = len(base_ws)
hdr_line_idx = src[:m.start()].count("\n")  # 0-based

# índice de la primera línea del cuerpo
i = hdr_line_idx + 1
# eliminar 'pass' suelto justo tras el header
while i < len(lines) and lines[i].strip() == "":
    i += 1
if i < len(lines) and lines[i].strip() == "pass":
    # quita ese pass "de relleno"
    del lines[i]

# recomputa src parcial para encontrar fin de bloque _middleware
src2 = "\n".join(lines)
# vuelve a localizar header porque se pudo mover el offset
m2 = re.search(r'(?m)^([ ]*)def[ ]+_middleware\([^)]*\)\s*:\s*$', src2)
hdr_line_idx = src2[:m2.start()].count("\n")
base_ws = m2.group(1); base = len(base_ws)

# hallar fin del bloque: primera línea (no vacía) con indent < base
j = hdr_line_idx + 1
end_idx = len(lines)
while j < len(lines):
    L = lines[j]
    if L.strip() != "" and (len(L) - len(L.lstrip(" ")) ) <= base and not L.startswith(base_ws + " "):
        end_idx = j
        break
    j += 1

# asegurar que dentro del bloque exista def _app(...)
block = lines[hdr_line_idx+1:end_idx]
has_def_app = any(re.match(r'^\s*def\s+_app\s*\(', L) for L in block)

# asegurar 'return _app' al cierre del bloque
has_return_app = any(re.match(rf'^{re.escape(base_ws)}return\s+_app\s*$', L) for L in lines[hdr_line_idx:end_idx])

if has_def_app and not has_return_app:
    lines.insert(end_idx, f"{base_ws}return _app")
    end_idx += 1
    print("• añadido 'return _app' al final de _middleware")

# ===== 2) inyectar _root_force_mw si falta =====
src3 = "\n".join(lines)
has_root_mw_def = re.search(r'(?m)^def\s+_root_force_mw\s*\(\s*inner\s*\)\s*:\s*$', src3) is not None
if not has_root_mw_def:
    BLOCK = r'''
def _root_force_mw(inner):
    # Middleware raíz: CORS + OPTIONS para /api/*
    def _mw(environ, start_response):
        path   = (environ.get("PATH_INFO") or "")
        method = (environ.get("REQUEST_METHOD") or "GET").upper()
        origin = environ.get("HTTP_ORIGIN")
        def _cors_headers(headers):
            if not origin:
                return headers
            low = {k.lower(): i for i,(k,_) in enumerate(headers)}
            def upsert(k, v):
                i = low.get(k.lower())
                if i is None:
                    headers.append((k, v))
                    low[k.lower()] = len(headers)-1
                else:
                    k0,_ = headers[i]; headers[i] = (k0, v)
            upsert("Access-Control-Allow-Origin", origin)
            upsert("Vary", "Origin")
            upsert("Access-Control-Allow-Credentials", "true")
            upsert("Access-Control-Expose-Headers", "Link, X-Next-Cursor, X-Summary-Applied, X-Summary-Limit")
            return headers
        if method == "OPTIONS" and path.startswith("/api/"):
            hdrs = [
                ("Content-Type", "application/json; charset=utf-8"),
                ("Access-Control-Allow-Methods", "GET,POST,OPTIONS"),
                ("Access-Control-Allow-Headers", "Content-Type, Accept"),
                ("Access-Control-Max-Age", "600"),
            ]
            hdrs = _cors_headers(hdrs)
            start_response("204 No Content", hdrs)
            return [b""]
        st = {"status": "200 OK", "headers": []}
        def sr(status, headers, exc_info=None):
            st["status"] = status; st["headers"] = list(headers)
            return (lambda data: None)
        body_iter = inner(environ, sr)
        body = b"".join(body_iter) if hasattr(body_iter, "__iter__") else (body_iter or b"")
        headers = _cors_headers(st["headers"])
        headers = [(k,v) for (k,v) in headers if k.lower() != "content-length"]
        start_response(st["status"], headers)
        return [body]
    return _mw
'''.lstrip("\n")
    # Inserta antes de la primera asignación de app = _middleware(...)
    m_app = re.search(r'(?m)^app\s*=\s*_middleware\(', src3)
    insert_at = m_app.start() if m_app else len(src3)
    src3 = src3[:insert_at] + "\n" + BLOCK + "\n" + src3[insert_at:]
    lines = src3.split("\n")
    print("• inyectado _root_force_mw (CORS/OPTIONS)")

# ===== 3) asegurar hook "app = _root_force_mw(app)" tras "app = _middleware(...)" =====
src4 = "\n".join(lines)
if "app = _root_force_mw(app)" not in src4:
    m_app = re.search(r'(?m)^app\s*=\s*_middleware\([^)]*\)\s*$', src4)
    if m_app:
        hook = [
            "try:",
            "    _root_force_mw  # noqa",
            "except NameError:",
            "    pass",
            "else:",
            "    try:",
            "        app = _root_force_mw(app)",
            "    except Exception:",
            "        pass",
        ]
        pos = m_app.end()
        src4 = src4[:pos] + "\n" + "\n".join(hook) + "\n" + src4[pos:]
        print("• aplicado hook CORS detrás de app=_middleware")
    lines = src4.split("\n")

out = "\n".join(lines)
if out == src:
    print("OK: no había nada para cambiar")
    if not gate(): sys.exit(1)
    sys.exit(0)

bak = W.with_suffix(".py.patch_mw_return_and_cors.bak")
if not bak.exists():
    shutil.copyfile(W, bak)
W.write_text(out, encoding="utf-8")
print(f"patched: _middleware retorna _app; CORS listo | backup={bak.name}")

if not gate(): sys.exit(1)
