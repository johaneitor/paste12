#!/usr/bin/env python3
import pathlib, re, sys, py_compile

P = pathlib.Path("wsgiapp/__init__.py")
s = P.read_text(encoding="utf-8")

if "class _MaxTTLGuard" not in s:
    inject = r"""
# === APPEND-ONLY: Max TTL guard (cap hours to 3 months by default) ===
class _MaxTTLGuard:
    def __init__(self, inner):
        self.inner = inner

    def __call__(self, environ, start_response):
        try:
            path = (environ.get("PATH_INFO") or "")
            method = (environ.get("REQUEST_METHOD") or "GET").upper()
            if method == "POST" and path == "/api/notes":
                import os, json, io
                # reversible por ENV
                if (environ.get("HTTP_DISABLE_MAX_TTL") or os.getenv("DISABLE_MAX_TTL","0")).strip().lower() in ("1","true","yes","on"):
                    return self.inner(environ, start_response)
                try:
                    max_h = int((environ.get("HTTP_MAX_TTL_HOURS") or os.getenv("MAX_TTL_HOURS","2160")).strip() or "2160")
                except Exception:
                    max_h = 2160
                ctype = (environ.get("CONTENT_TYPE") or "").lower()
                if "application/json" in ctype:
                    try:
                        length = int(environ.get("CONTENT_LENGTH") or "0")
                    except Exception:
                        length = 0
                    raw = environ["wsgi.input"].read(length) if length > 0 else b"{}"
                    try:
                        data = json.loads(raw.decode("utf-8") or "{}")
                    except Exception:
                        data = {}
                    # clamp defensivo de nombres comunes
                    keys = ("hours","expires_hours","ttl","ttl_hours")
                    touched = False
                    for k in keys:
                        if isinstance(data.get(k), (int, float)):
                            v = int(data[k])
                            if v < 1: v = 1
                            if v > max_h: v = max_h
                            data[k] = v
                            touched = True
                    if touched:
                        nr = json.dumps(data, ensure_ascii=False).encode("utf-8")
                        environ["wsgi.input"] = io.BytesIO(nr)
                        environ["CONTENT_LENGTH"] = str(len(nr))
                        def sr(status, headers, exc_info=None):
                            headers = list(headers) + [("X-Max-TTL-Hours", str(max_h))]
                            return start_response(status, headers, exc_info)
                        return self.inner(environ, sr)
        except Exception:
            pass
        return self.inner(environ, start_response)
"""
    s += inject

# envolver una sola vez (idempotente)
if re.search(r"\b_MAX_TTL_WRAPPED\b", s) is None:
    s += r"""
# --- envolver outermost: Max TTL guard ---
try:
    _MAX_TTL_WRAPPED
except NameError:
    try:
        app = _MaxTTLGuard(app)
    except Exception:
        pass
    _MAX_TTL_WRAPPED = True
"""

P.write_text(s, encoding="utf-8")
py_compile.compile(str(P), doraise=True)
print("patched: _MaxTTLGuard aplicado (idempotente)")
