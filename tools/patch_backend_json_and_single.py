#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)
src = W.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n")

# 1) Inserta helper _parse_post_note si no existe
if "_parse_post_note(" not in src:
    helper = r'''
def _parse_post_note(environ):
    """Devuelve (code, payload) o (None, {"text": "..."}). Tolerante a JSON, FORM y texto plano."""
    try:
        ctype = (environ.get("CONTENT_TYPE") or "").lower()
        clen  = environ.get("CONTENT_LENGTH") or ""
        try:
            n = int(clen) if clen.strip() else 0
        except Exception:
            n = 0
        # lee hasta n bytes si n>0; si no, best-effort
        raw = environ["wsgi.input"].read(n) if n > 0 else (environ["wsgi.input"].read() or b"")
        text = None
        if "application/json" in ctype:
            try:
                import json as _json
                obj = _json.loads((raw or b"").decode("utf-8") or "{}")
                if isinstance(obj, dict):
                    # Acepta top-level "text" o wrappers frecuentes
                    text = obj.get("text") \
                           or (obj.get("item") or {}).get("text") \
                           or (obj.get("data") or {}).get("text")
                elif isinstance(obj, str):
                    text = obj
            except Exception:
                pass  # caerá a FORM/texto
        if text is None and "application/x-www-form-urlencoded" in ctype:
            from urllib.parse import parse_qs
            qd = parse_qs((raw or b"").decode("utf-8"), keep_blank_values=True)
            text = (qd.get("text") or [""])[0]
        if text is None and "text/plain" in ctype:
            text = (raw or b"").decode("utf-8")
        # Best-effort extra: si nada funcionó y hay algo legible, intenta parsear como JSON y si no, como texto
        if text is None and raw:
            try:
                import json as _json
                obj = _json.loads((raw or b"").decode("utf-8"))
                if isinstance(obj, dict):
                    text = obj.get("text") or (obj.get("item") or {}).get("text")
                elif isinstance(obj, str):
                    text = obj
            except Exception:
                text = (raw or b"").decode("utf-8")
        if text is None:
            return 400, {"ok": False, "error": "text_required"}
        return None, {"text": text}
    except Exception as e:
        return 500, {"ok": False, "error": f"parse_failed: {e}"}
'''.lstrip("\n")
    # inserta antes de def _middleware(…) para no romper offsets
    m = re.search(r'(?m)^def\s+_middleware\(', src)
    pos = m.start() if m else len(src)
    src = src[:pos] + "\n" + helper + "\n" + src[pos:]

# 2) Reescribe el bloque POST /api/notes para usar el helper (idempotente)
pat_post = re.compile(
    r'(?m)^(?P<ind>[ \t]*)if\s+path\s*==\s*"/api/notes"\s*and\s*method\s*==\s*"POST"\s*:\s*\n'
    r'(?P<body>(?:\s+.*\n)+?)'  # cuerpo del bloque hasta el primer dedent del mismo nivel
)
m = pat_post.search(src)
if m:
    ind = m.group("ind")
    # Bloque nuevo, seguro e idempotente
    new_body = (
        f"{ind}    _code_payload, _data = _parse_post_note(environ)\n"
        f"{ind}    if _code_payload is not None:\n"
        f"{ind}        code, payload = _code_payload, _data\n"
        f"{ind}    else:\n"
        f"{ind}        try:\n"
        f"{ind}            code, payload = _insert_note(_data)\n"
        f"{ind}        except Exception as e:\n"
        f"{ind}            code, payload = 500, {{\"ok\": False, \"error\": str(e)}}\n"
        f"{ind}    status, headers, body = _json(code, payload)\n"
        f"{ind}    return _finish(start_response, status, headers, body, method)\n"
    )
    # Sustituye sólo si aún no usamos el helper (evitar doble parche)
    if "_parse_post_note(" not in m.group("body"):
        src = src[:m.start()] + m.group(0).splitlines()[0] + "\n" + new_body + src[m.end():]

# 3) Inyecta flag de single-note (data-single/data-note-id) al servir "/" con ?id=
# Buscamos en _app el branch que sirve el index vía _serve_index_html()
pat_index = re.compile(
    r'(?m)^([ \t]*)if\s+path\s+in\s*\(\s*"/",\s*"/index\.html"\s*\)\s*and\s*method\s+in\s*\(\s*"GET",\s*"HEAD"\s*\)\s*:\s*\n'
    r'([ \t]*).*?\n'  # línea siguiente
    r'([ \t]*)status,\s*headers,\s*body\s*=\s*_serve_index_html\(\)\s*\n'
    r'([ \t]*)return\s+_finish\(start_response, status, headers, body, method\)\s*'
)
m = pat_index.search(src)
if m:
    base = m.group(1)
    # Insertamos reescritura de body si hay ?id= en qs
    inject = (
        f"{base}    # Inyección de modo single-note si viene ?id= en la query\n"
        f"{base}    try:\n"
        f"{base}        from urllib.parse import parse_qs as _pq\n"
        f"{base}        _id = None\n"
        f"{base}        if qs:\n"
        f"{base}            _q = _pq(qs, keep_blank_values=True)\n"
        f"{base}            _idv = _q.get('id') or _q.get('note')\n"
        f"{base}            if _idv and _idv[0].isdigit():\n"
        f"{base}                _id = _idv[0]\n"
        f"{base}        if _id:\n"
        f"{base}            try:\n"
        f"{base}                _b = body if isinstance(body, (bytes, bytearray)) else (body or b\"\")\n"
        f"{base}                _b = _b.replace(b\"<body\", f\"<body data-single=\\\"1\\\" data-note-id=\\\"{{_id}}\\\"\".encode('utf-8'), 1)\n"
        f"{base}                body = _b\n"
        f"{base}            except Exception:\n"
        f"{base}                pass\n"
        f"{base}    except Exception:\n"
        f"{base}        pass\n"
    )
    src = src[:m.start()] + \
          f"{m.group(1)}if path in (\"/\", \"/index.html\") and method in (\"GET\",\"HEAD\"):\n" + \
          f"{m.group(2)}if inner_app is None or os.environ.get(\"FORCE_BRIDGE_INDEX\") == \"1\":\n" + \
          f"{m.group(3)}status, headers, body = _serve_index_html()\n" + \
          inject + \
          f"{m.group(4)}return _finish(start_response, status, headers, body, method)\n" + \
          src[m.end():]

# Backup y escritura
bak = W.with_suffix(".py.backend_json_single.bak")
if not bak.exists():
    shutil.copyfile(W, bak)
W.write_text(src, encoding="utf-8")
py_compile.compile(str(W), doraise=True)
print("patched: backend JSON+single-note | backup=", bak.name)
