#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile
W = pathlib.Path("wsgiapp/__init__.py")
s = W.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n")
if "\t" in s: s = s.replace("\t","    ")
changed = False

BLOCK = r'''
# === Outermost: Pagination guards (limit clamp + depth<=200) ===
try:
    _PAGINATION_GUARDS_WRAPPED
except NameError:
    import json as _json_mod
    import re as _re
    from urllib.parse import parse_qsl, urlencode
    class _ClampAndDepthWrapper:
        def __init__(self, inner):
            self.inner = inner
        def __call__(self, environ, start_response):
            path = (environ.get("PATH_INFO") or "")
            method = (environ.get("REQUEST_METHOD") or "GET").upper()
            if method == "GET" and path.rstrip("/").startswith("/api/notes"):
                # clamp limit in query
                qs = environ.get("QUERY_STRING","")
                qd = dict(parse_qsl(qs, keep_blank_values=True))
                clamped = False
                try:
                    lim = int(qd.get("limit","") or "0")
                    newlim = max(1, min(50, lim)) if lim>0 else None
                    if newlim is not None:
                        if str(newlim) != qd.get("limit"):
                            qd["limit"] = str(newlim); clamped=True
                except Exception:
                    pass
                # track depth
                try:
                    depth = int(qd.get("depth","") or "1")
                    if depth <= 0: depth = 1
                except Exception:
                    depth = 1
                environ["QUERY_STRING"] = urlencode(qd, doseq=True)

                st = {"status": "", "headers": []}
                def sr(status, headers, exc_info=None):
                    st["status"]=status; st["headers"]=list(headers)
                    return (lambda x: None)
                it = self.inner(environ, sr)
                body = b"".join(it)
                headers = st["headers"]
                status = st["status"] or "200 OK"
                # add clamp header if needed
                if clamped:
                    headers.append(("X-Limit-Clamped","50"))
                # try to enforce depth <= 200
                try:
                    data = _json_mod.loads(body.decode("utf-8"))
                    if isinstance(data, dict):
                        next_obj = data.get("next")
                        next_depth = depth + 1
                        if next_depth > 200:
                            data.pop("next", None)
                            # kill Link header
                            headers = [(k,v) for (k,v) in headers if k.lower()!="link"]
                            headers.append(("X-Page-Depth", str(depth)))
                            headers.append(("X-Pagination-Closed","1"))
                        else:
                            if isinstance(next_obj, dict):
                                next_obj["depth"] = next_depth
                                data["next"] = next_obj
                            # rewrite X-Next-Cursor if present
                            new_xnext = _json_mod.dumps(data.get("next",{}), default=str)
                            newh=[]
                            have_xnext=False
                            for k,v in headers:
                                if k.lower()=="x-next-cursor":
                                    newh.append((k,new_xnext)); have_xnext=True
                                else:
                                    newh.append((k,v))
                            headers = newh
                            # append depth to Link: next
                            newh=[]
                            for k,v in headers:
                                if k.lower()=="link":
                                    m=_re.search(r'<([^>]+)>\s*;\s*rel="next"', v)
                                    if m:
                                        url=m.group(1)
                                        sep="&" if "?" in url else "?"
                                        v=v.replace(url, f"{url}{sep}depth={next_depth}")
                                    newh.append((k,v))
                                else:
                                    newh.append((k,v))
                            headers = newh
                        body = _json_mod.dumps(data, default=str).encode("utf-8")
                        headers = [(k,v) for (k,v) in headers if k.lower()!="content-length"]
                        headers.append(("Content-Length", str(len(body))))
                except Exception:
                    pass
                start_response(status, headers)
                return [body]
            return self.inner(environ, start_response)
    try:
        app = _ClampAndDepthWrapper(app)
    except Exception:
        pass
    _PAGINATION_GUARDS_WRAPPED = True
'''
if "class _ClampAndDepthWrapper" not in s:
    if not s.endswith("\n"): s += "\n"
    s += "\n" + BLOCK.strip() + "\n"
    changed = True

if changed:
    bak = W.with_suffix(".py.patch_pagination_guards.bak")
    if not bak.exists(): shutil.copyfile(W, bak)
    W.write_text(s, encoding="utf-8")
    print("patched: pagination guards | backup=", bak.name)

py_compile.compile(str(W), doraise=True)
print("✓ py_compile OK")
