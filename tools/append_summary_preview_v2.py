#!/usr/bin/env python3
import pathlib, py_compile, re

W = pathlib.Path("wsgiapp/__init__.py")
s = W.read_text(encoding="utf-8")
changed = False

def ensure_import(mod):
    global s
    if re.search(rf'\bimport +{re.escape(mod)}\b', s) or re.search(rf'from +{re.escape(mod)} +import\b', s):
        return
    # inserta de forma inocua
    if "import os" in s:
        s = s.replace("import os", "import os\nimport "+mod, 1)
    else:
        s = "import "+mod+"\n"+s

# imports mínimos
ensure_import("json"); changed = True

if "class _SummaryPreviewWrapperV2" not in s:
    s += r"""

# === APPEND-ONLY: Summary preview V2 (fix Content-Length y start_response) ===
class _SummaryPreviewWrapperV2:
    def __init__(self, inner):
        self.inner = inner

    def _truth(self, v:str):
        return (v or "").strip().lower() in ("1","true","yes","on")

    def _enabled(self, env):
        if self._truth(env.get("HTTP_DISABLE_SUMMARY_PREVIEW")):
            return False
        import os
        if "DISABLE_SUMMARY_PREVIEW" in os.environ:
            return not self._truth(os.environ.get("DISABLE_SUMMARY_PREVIEW"))
        return True

    def _limit(self, env):
        import os
        h = env.get("HTTP_SUMMARY_PREVIEW_LIMIT")
        if h and h.isdigit(): return max(1, min(500, int(h)))
        e = os.environ.get("SUMMARY_PREVIEW_LIMIT")
        if e and e.isdigit(): return max(1, min(500, int(e)))
        return 20

    def _mk_summary(self, txt, lim):
        txt = txt or ""
        return txt if len(txt) <= lim else (txt[:lim] + "…")

    def _apply(self, obj, lim):
        if isinstance(obj, dict):
            if "items" in obj and isinstance(obj["items"], list):
                for it in obj["items"]:
                    if isinstance(it, dict):
                        if not it.get("summary"):
                            base = it.get("text") or it.get("content") or ""
                            it["summary"] = self._mk_summary(base, lim)
                            it.setdefault("has_more", len(base) > len(it["summary"]))
            if "item" in obj and isinstance(obj["item"], dict):
                it = obj["item"]
                if not it.get("summary"):
                    base = it.get("text") or it.get("content") or ""
                    it["summary"] = self._mk_summary(base, lim)
                    it.setdefault("has_more", len(base) > len(it["summary"]))
        return obj

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        method = (environ.get("REQUEST_METHOD") or "GET").upper()

        # Sólo afecta GET /api/notes...
        if method == "GET" and path.startswith("/api/notes"):
            if not self._enabled(environ):
                return self.inner(environ, start_response)

            captured = {"status": None, "headers": []}
            chunks = []

            def fake_start(status, headers, exc_info=None):
                captured["status"] = status
                captured["headers"] = list(headers)
                # write() collector (por si el inner lo usa)
                def _w(b):
                    chunks.append(b)
                return _w

            app_iter = self.inner(environ, fake_start)
            try:
                for c in app_iter:
                    chunks.append(c)
            finally:
                try:
                    close = getattr(app_iter, "close", None)
                    if callable(close): close()
                except Exception:
                    pass

            status = captured["status"] or "200 OK"
            headers = captured["headers"] or []
            body = b"".join(chunks)

            # Si no es 200 o no es JSON -> devolvemos tal cual pero re-empaquetado
            ct = next((v for (k,v) in headers if k.lower()=="content-type"), "application/json; charset=utf-8").lower()
            if "200" not in status or "application/json" not in ct:
                start_response(status, headers)
                return [body]

            # Reescritura segura del cuerpo y Content-Length
            try:
                obj = json.loads(body.decode("utf-8"))
                lim = self._limit(environ)
                obj2 = self._apply(obj, lim)
                new_body = json.dumps(obj2, ensure_ascii=False, separators=(",",":")).encode("utf-8")
                # headers: reemplazar Content-Length y agregar marcas
                new_headers = [(k,v) for (k,v) in headers if k.lower()!="content-length"]
                new_headers.append(("Content-Length", str(len(new_body))))
                new_headers.append(("X-Summary-Applied","1"))
                new_headers.append(("X-Summary-Limit", str(lim)))
                start_response(status, new_headers)
                return [new_body]
            except Exception:
                # ante error, devolvemos intacto
                start_response(status, headers)
                return [body]

        # resto pasa directo
        return self.inner(environ, start_response)
"""
    changed = True

# envolver outermost con V2 una sola vez
if "SUMMARY_PREVIEW_WRAPPED_V2 = True" not in s:
    s += r"""
# --- envolver outermost (summary preview V2) ---
try:
    SUMMARY_PREVIEW_WRAPPED_V2
except NameError:
    try:
        app = _SummaryPreviewWrapperV2(app)
    except Exception:
        pass
    SUMMARY_PREVIEW_WRAPPED_V2 = True
"""
    changed = True

if not changed:
    print("OK: Summary V2 ya estaba"); exit(0)

W.write_text(s, encoding="utf-8")
py_compile.compile(str(W), doraise=True)
print("patched: Summary Preview V2 (headers correctos)")
