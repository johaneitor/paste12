#!/usr/bin/env python3
import pathlib, py_compile

P = pathlib.Path("wsgiapp/__init__.py")
s = P.read_text(encoding="utf-8")
changed = False

# 0) imports seguros al tope (idempotente)
if "import json" not in s:
    s = s.replace("\nimport os", "\nimport os\nimport json") if "import os" in s else "import json\n" + s
    changed = True

# 1) inyectar wrapper si falta
if "class _SummaryPreviewWrapper" not in s:
    s += r"""

# === APPEND-ONLY: Summary preview para notas (20 chars + '…', con 'ver más' en UI) ===
class _SummaryPreviewWrapper:
    def __init__(self, inner):
        self.inner = inner

    def _is_enabled(self, environ):
        def _truth(v):
            return (v or "").strip().lower() in ("1","true","yes","on")
        # header tiene prioridad para poder desactivar sin redeploy
        if _truth(environ.get("HTTP_DISABLE_SUMMARY_PREVIEW")):
            return False
        # env (default on)
        import os
        if "DISABLE_SUMMARY_PREVIEW" in os.environ:
            return not _truth(os.environ.get("DISABLE_SUMMARY_PREVIEW"))
        return True

    def _limit(self, environ):
        import os
        hdr = environ.get("HTTP_SUMMARY_PREVIEW_LIMIT")
        if hdr and hdr.isdigit():
            return max(1, min(500, int(hdr)))
        env = os.environ.get("SUMMARY_PREVIEW_LIMIT")
        if env and env.isdigit():
            return max(1, min(500, int(env)))
        return 20

    def _add_summary(self, obj, limit):
        # obj puede ser {"items":[...]}, o {"item":{...}}
        def _mk(txt: str) -> str:
            txt = txt or ""
            return txt if len(txt) <= limit else (txt[:limit] + "…")
        if isinstance(obj, dict):
            if "items" in obj and isinstance(obj["items"], list):
                for it in obj["items"]:
                    if isinstance(it, dict):
                        if "summary" not in it or not it.get("summary"):
                            base = it.get("text") or it.get("content") or ""
                            it["summary"] = _mk(base)
                            # pista opcional para UI
                            it.setdefault("has_more", len(base) > limit)
            if "item" in obj and isinstance(obj["item"], dict):
                it = obj["item"]
                if "summary" not in it or not it.get("summary"):
                    base = it.get("text") or it.get("content") or ""
                    it["summary"] = _mk(base)
                    it.setdefault("has_more", len(base) > limit)
        return obj

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        method = (environ.get("REQUEST_METHOD") or "GET").upper()
        # sólo GET /api/notes...
        if method == "GET" and path.startswith("/api/notes"):
            if not self._is_enabled(environ):
                return self.inner(environ, start_response)

            status_headers = {}
            def _cap_sr(status, headers, exc_info=None):
                status_headers["status"] = status
                status_headers["headers"] = headers[:]
                return start_response(status, headers, exc_info)

            # llamamos a la app interna
            app_iter = self.inner(environ, _cap_sr)

            try:
                body = b"".join(app_iter)
            finally:
                try:
                    close = getattr(app_iter, "close", None)
                    if callable(close):
                        close()
                except Exception:
                    pass

            status = status_headers.get("status","200 OK")
            headers = status_headers.get("headers", [])

            # Sólo si es JSON y 200
            ct = next((v for (k,v) in headers if k.lower()=="content-type"), "application/json").lower()
            if "200" in status and "application/json" in ct:
                try:
                    obj = json.loads(body.decode("utf-8"))
                    lim = self._limit(environ)
                    new = self._add_summary(obj, lim)
                    new_body = json.dumps(new, ensure_ascii=False, separators=(",",":")).encode("utf-8")
                    # actualizar Content-Length y marcar headers
                    new_headers = [(k,v) for (k,v) in headers if k.lower()!="content-length"]
                    new_headers.append(("Content-Length", str(len(new_body))))
                    new_headers.append(("X-Summary-Applied","1"))
                    new_headers.append(("X-Summary-Limit", str(lim)))
                    def _sr2(status, hdrs, exc_info=None):
                        return start_response(status, new_headers, exc_info)
                    return [new_body]
                except Exception:
                    # ante cualquier error, devolvemos intacto
                    return [body]
            else:
                return [body]
        # resto pasa directo
        return self.inner(environ, start_response)
"""
    changed = True

# 2) envolver una sola vez
if "SUMMARY_PREVIEW_WRAPPED = True" not in s:
    s += r"""
# --- envolver outermost (summary preview) ---
try:
    SUMMARY_PREVIEW_WRAPPED
except NameError:
    try:
        app = _SummaryPreviewWrapper(app)
    except Exception:
        pass
    SUMMARY_PREVIEW_WRAPPED = True
"""
    changed = True

if not changed:
    print("OK: _SummaryPreviewWrapper ya estaba aplicado"); exit(0)

# Sanity compile
P.write_text(s, encoding="utf-8")
py_compile.compile(str(P), doraise=True)
print("patched: _SummaryPreviewWrapper añadido y aplicado")
