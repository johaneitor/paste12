#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile
W = pathlib.Path("wsgiapp/__init__.py")
s = W.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n")
if "\t" in s: s = s.replace("\t","    ")
changed = False

BLOCK = r'''
# === Outermost: Feed summary/has_more augmentation ===
try:
    _SUMMARY_AUGMENT_WRAPPED
except NameError:
    import json as _json_mod
    class _SummaryAugmentWrapper:
        LIMIT = 40
        def __init__(self, inner): self.inner=inner
        def _mk_summary(self, txt):
            if not isinstance(txt, str): return "", False
            t = txt.strip()
            if len(t) <= self.LIMIT: return t, False
            cut = t[:self.LIMIT]
            # cortar en último espacio si existe para no partir palabra
            sp = cut.rfind(" ")
            if sp >= 20: cut = cut[:sp]
            return cut + "…", True
        def __call__(self, environ, start_response):
            path = (environ.get("PATH_INFO") or "")
            method = (environ.get("REQUEST_METHOD") or "GET").upper()
            if method=="GET" and path.rstrip("/").startswith("/api/notes"):
                st = {"status":"","headers":[]}
                def sr(status, headers, exc_info=None):
                    st["status"]=status; st["headers"]=list(headers)
                    return (lambda x: None)
                it = self.inner(environ, sr)
                body = b"".join(it)
                try:
                    data = _json_mod.loads(body.decode("utf-8"))
                    items = data.get("items")
                    if isinstance(items, list):
                        for it in items:
                            txt = it.get("text","")
                            summ, more = self._mk_summary(txt)
                            it["summary"] = summ
                            it["has_more"] = bool(more)
                        body = _json_mod.dumps(data, default=str).encode("utf-8")
                        hdrs = [(k,v) for (k,v) in st["headers"] if k.lower()!="content-length"]
                        hdrs.append(("X-Preview-Limit", str(self.LIMIT)))
                        hdrs.append(("Content-Length", str(len(body))))
                        start_response(st["status"] or "200 OK", hdrs)
                        return [body]
                except Exception:
                    pass
                start_response(st["status"] or "200 OK", st["headers"])
                return [body]
            return self.inner(environ, start_response)
    try:
        app = _SummaryAugmentWrapper(app)
    except Exception:
        pass
    _SUMMARY_AUGMENT_WRAPPED = True
'''
if "class _SummaryAugmentWrapper" not in s:
    if not s.endswith("\n"): s += "\n"
    s += "\n" + BLOCK.strip() + "\n"
    changed = True

if changed:
    bak = W.with_suffix(".py.patch_summary_has_more.bak")
    if not bak.exists(): shutil.copyfile(W, bak)
    W.write_text(s, encoding="utf-8")
    print("patched: summary/has_more | backup=", bak.name)

py_compile.compile(str(W), doraise=True)
print("✓ py_compile OK")
