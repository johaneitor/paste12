#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile
W = pathlib.Path("wsgiapp/__init__.py")
s = W.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n")
if "\t" in s: s = s.replace("\t","    ")
changed = False

BLOCK = r'''
# === Outermost: Text bounds on POST /api/notes (min/max) ===
try:
    _TEXT_BOUNDS_WRAPPED
except NameError:
    import io, json as _json_mod
    from urllib.parse import parse_qs
    class _TextBoundsWrapper:
        MIN_LEN = 40
        MAX_LEN = 2000
        def __init__(self, inner): self.inner=inner
        def __call__(self, environ, start_response):
            path = (environ.get("PATH_INFO") or "")
            method = (environ.get("REQUEST_METHOD") or "GET").upper()
            if method=="POST" and path.rstrip("/") == "/api/notes":
                ctype = (environ.get("CONTENT_TYPE","").split(";")[0] or "").lower()
                try:
                    clen = int(environ.get("CONTENT_LENGTH") or "0")
                except Exception:
                    clen = 0
                raw = environ.get("wsgi.input").read(clen) if clen>0 else b""
                # reinyectar para el inner
                environ["wsgi.input"] = io.BytesIO(raw)
                text = None
                try:
                    if ctype == "application/json":
                        obj = _json_mod.loads(raw.decode("utf-8") or "{}")
                        text = (obj.get("text") or "")
                    elif ctype == "application/x-www-form-urlencoded":
                        qs = parse_qs(raw.decode("utf-8"), keep_blank_values=True)
                        text = (qs.get("text",[ ""])[0] or "")
                except Exception:
                    text = None
                if isinstance(text, str):
                    t = text.strip()
                    if len(t) < self.MIN_LEN:
                        body = _json_mod.dumps({"ok": False, "error":"text_too_short","min": self.MIN_LEN}).encode("utf-8")
                        start_response("400 Bad Request", [("Content-Type","application/json; charset=utf-8"),
                                                           ("Content-Length", str(len(body)))])
                        return [body]
                    if len(t) > self.MAX_LEN:
                        body = _json_mod.dumps({"ok": False, "error":"text_too_long","max": self.MAX_LEN}).encode("utf-8")
                        start_response("413 Payload Too Large", [("Content-Type","application/json; charset=utf-8"),
                                                                 ("Content-Length", str(len(body)))])
                        return [body]
            return self.inner(environ, start_response)
    try:
        app = _TextBoundsWrapper(app)
    except Exception:
        pass
    _TEXT_BOUNDS_WRAPPED = True
'''
if "class _TextBoundsWrapper" not in s:
    if not s.endswith("\n"): s += "\n"
    s += "\n" + BLOCK.strip() + "\n"
    changed = True

if changed:
    bak = W.with_suffix(".py.patch_text_bounds.bak")
    if not bak.exists(): shutil.copyfile(W, bak)
    W.write_text(s, encoding="utf-8")
    print("patched: text bounds | backup=", bak.name)

py_compile.compile(str(W), doraise=True)
print("✓ py_compile OK")
