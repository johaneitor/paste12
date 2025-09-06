#!/usr/bin/env python3
import pathlib, re, io, json, sys, shutil

W = pathlib.Path("wsgiapp/__init__.py")
s = W.read_text(encoding="utf-8")

changed = False

if "class _AcceptJsonOrFormNotes" not in s:
    s += r"""

# === Accept JSON or Form for POST /api/notes (outermost, idempotent) ===
class _AcceptJsonOrFormNotes:
    def __init__(self, inner):
        self.inner = inner

    def _resp_json(self, start_response, code, payload):
        import json as _json
        body = _json.dumps(payload, default=str).encode("utf-8")
        start_response(f"{code} OK", [
            ("Content-Type","application/json; charset=utf-8"),
            ("Content-Length", str(len(body))),
            ("X-WSGI-Bridge","1"),
        ])
        return [body]

    def _parse_payload(self, environ):
        # Devuelve (text, hours|None), leyendo primero JSON y luego form.
        try:
            ctype = (environ.get("CONTENT_TYPE") or "").split(";")[0].strip().lower()
        except Exception:
            ctype = ""
        try:
            clen = int(environ.get("CONTENT_LENGTH") or "0")
        except Exception:
            clen = 0
        try:
            raw = environ["wsgi.input"].read(clen) if clen > 0 else b""
        except Exception:
            raw = b""

        text = None
        hours = None

        # JSON
        if ctype == "application/json" and raw:
            try:
                obj = json.loads(raw.decode("utf-8","ignore"))
                text = (obj.get("text") or "").strip()
                if "hours" in obj:
                    try:
                        hours = int(obj.get("hours"))
                    except Exception:
                        hours = None
            except Exception:
                pass

        # Form fallback (incluye el caso de JSON inválido o vacío)
        if not text:
            try:
                from urllib.parse import parse_qs
                form = parse_qs(raw.decode("utf-8","ignore"), keep_blank_values=True)
                text = (form.get("text", [""])[0] or "").strip()
                if "hours" in form:
                    try:
                        hours = int((form.get("hours",[None])[0]) or "0")
                    except Exception:
                        hours = None
            except Exception:
                pass

        return text, hours

    def __call__(self, environ, start_response):
        try:
            path = (environ.get("PATH_INFO") or "")
            method = (environ.get("REQUEST_METHOD","GET") or "GET").upper()
            if method == "POST" and path == "/api/notes":
                import os, urllib.parse, io as _io
                text, hours = self._parse_payload(environ)

                min_chars = 10
                try:
                    min_chars = int(os.environ.get("MIN_TEXT_CHARS","10") or "10")
                except Exception:
                    pass

                if not text or len(text) < min_chars:
                    return self._resp_json(start_response, 400, {"ok": False, "error": "text_required"})

                # Reinyectar como form-urlencoded para no tocar el handler original
                pairs = [("text", text)]
                if hours is not None:
                    pairs.append(("hours", str(hours)))
                form = "&".join(urllib.parse.quote(k, safe="") + "=" + urllib.parse.quote(v, safe="")
                                for k, v in pairs).encode("utf-8")

                environ["CONTENT_TYPE"] = "application/x-www-form-urlencoded"
                environ["CONTENT_LENGTH"] = str(len(form))
                environ["wsgi.input"] = _io.BytesIO(form)

        except Exception:
            # Si algo raro ocurre, dejamos pasar al inner tal cual.
            pass

        return self.inner(environ, start_response)
"""
    changed = True

# Envolver outermost una sola vez
if "_NOTES_ACCEPT_WRAPPED = True" not in s:
    s += r"""
# --- wrap outermost: accept JSON or form for POST /api/notes ---
try:
    _NOTES_ACCEPT_WRAPPED
except NameError:
    try:
        app = _AcceptJsonOrFormNotes(app)
    except Exception:
        pass
    _NOTES_ACCEPT_WRAPPED = True
"""
    changed = True

if not changed:
    print("OK: wrapper ya presente")
else:
    bak = W.with_suffix(".py.accept_json_or_form.bak")
    if not bak.exists():
        shutil.copyfile(W, bak)
    W.write_text(s, encoding="utf-8")
    print("patched: _AcceptJsonOrFormNotes añadido y envuelto")

# Gate de compilación
import py_compile
py_compile.compile(str(W), doraise=True)
print("✓ py_compile OK")
