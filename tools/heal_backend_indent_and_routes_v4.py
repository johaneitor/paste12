#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)

src = W.read_text(encoding="utf-8", errors="ignore")
# Normalización dura de EOL/espacios
src = src.replace("\r\n","\n").replace("\r","\n").replace("\t","    ")

bak = W.with_suffix(".routes_v4.bak")
if not bak.exists():
    shutil.copyfile(W, bak)

def put(new_src):
    W.write_text(new_src, encoding="utf-8")

def canon_finish(indent=""):
    return (
f"""{indent}def _finish(start_response, status, headers, body, method, extra_headers=None):
{indent}    try:
{indent}        # Normaliza cuerpo y respeta HEAD
{indent}        if isinstance(body, str):
{indent}            body_bytes = body.encode("utf-8")
{indent}        elif isinstance(body, (bytes, bytearray)):
{indent}            body_bytes = bytes(body)
{indent}        else:
{indent}            body_bytes = b""
{indent}        if (method or "").upper() == "HEAD":
{indent}            body_bytes = b""
{indent}
{indent}        # Fusiona headers + extra y asegura Content-Length
{indent}        hdrs = list(headers or [])
{indent}        if extra_headers:
{indent}            hdrs.extend(list(extra_headers))
{indent}        if not any(k.lower()=="content-length" for k,_ in hdrs):
{indent}            hdrs.append(("Content-Length", str(len(body_bytes))))
{indent}
{indent}        start_response(status, hdrs)
{indent}        return [body_bytes]
{indent}    except Exception:
{indent}        try:
{indent}            start_response("500 Internal Server Error", [("Content-Type","text/plain; charset=utf-8")])
{indent}        except Exception:
{indent}            pass
{indent}        return [b"internal error"]
"""
    )

def ensure_finish(s):
    # Reemplaza cualquier _finish existente por el canónico, conservando indent
    m = re.search(r'(?ms)^([ ]*)def[ ]+_finish\s*\(\s*start_response\s*,\s*status\s*,\s*headers\s*,\s*body\s*,\s*method(?:\s*,\s*extra_headers\s*=\s*None)?\s*\)\s*:\s*(?:\n(?:(?:\1[ ]+).*\n)*)?', s)
    if m:
        ind = m.group(1)
        return s[:m.start()] + canon_finish(ind) + s[m.end():], True
    # No estaba: lo insertamos al inicio del módulo
    return canon_finish("") + s, True

def ensure_helper_single_attr(s):
    # Inserta helper _inject_single_attr si falta
    if re.search(r'(?m)^def[ ]+_inject_single_attr\(', s):
        return s, False
    helper = '''
def _inject_single_attr(body, nid):
    try:
        b = body if isinstance(body, (bytes, bytearray)) else (body or b"")
        if b:
            return b.replace(b"<body", f'<body data-single="1" data-note-id="{nid}"'.encode("utf-8"), 1)
    except Exception:
        pass
    return body
'''
    # lo insertamos después de _finish si existe, si no al inicio
    m = re.search(r'(?m)^def[ ]+_finish\(', s)
    if m:
        ins = s.find("\n", m.end())
        if ins == -1: ins = m.end()
        return s[:ins+1] + helper + s[ins+1:], True
    return helper + s, True

def replace_app_body(s):
    # Ubicar cabecera de def _app(...)
    m = re.search(r'(?m)^([ ]*)def[ ]+_app\s*\(\s*environ\s*,\s*start_response\s*\)\s*:\s*$', s)
    if not m:
        raise RuntimeError("no encontré 'def _app(environ, start_response):'")
    ind = m.group(1)
    start_line = s[:m.start()].count("\n")
    lines = s.split("\n")

    # Hallar fin del bloque actual de _app: la próxima def/class con indent <= ind
    def find_end(lines, hdr_idx, base_indent):
        for i in range(hdr_idx+1, len(lines)):
            L = lines[i]
            if re.match(r'^[ ]*$', L):  # línea vacía, ignora
                continue
            m2 = re.match(r'^([ ]*)(def|class)\b', L)
            if m2:
                if len(m2.group(1)) <= len(base_indent):
                    return i
        return len(lines)

    hdr_idx = start_line
    end_idx = find_end(lines, hdr_idx, ind)

    # Cuerpo canónico de _app (rutas mínimas estables)
    body = (
f"""{ind}def _app(environ, start_response):
{ind}    method = (environ.get("REQUEST_METHOD") or "GET").upper()
{ind}    path   = environ.get("PATH_INFO") or "/"
{ind}    qs     = environ.get("QUERY_STRING") or ""
{ind}
{ind}    # Index (bridge) + inyección de single flag por ?id= o ?note=
{ind}    if path in ("/", "/index.html") and method in ("GET","HEAD"):
{ind}        status, headers, body = _serve_index_html()
{ind}        try:
{ind}            if qs:
{ind}                from urllib.parse import parse_qs
{ind}                q = parse_qs(qs, keep_blank_values=True)
{ind}                _idv = q.get("id") or q.get("note")
{ind}                if _idv and _idv[0].isdigit():
{ind}                    body = _inject_single_attr(body, _idv[0])
{ind}        except Exception:
{ind}            pass
{ind}        return _finish(start_response, status, headers, body, method)
{ind}
{ind}    # Páginas estáticas
{ind}    if path == "/terms" and method in ("GET","HEAD"):
{ind}        status, headers, body = _html(200, _TERMS_HTML)
{ind}        return _finish(start_response, status, headers, body, method)
{ind}    if path == "/privacy" and method in ("GET","HEAD"):
{ind}        status, headers, body = _html(200, _PRIVACY_HTML)
{ind}        return _finish(start_response, status, headers, body, method)
{ind}
{ind}    # Health
{ind}    if path == "/api/health" and method in ("GET","HEAD"):
{ind}        status, headers, body = _json(200, {{ "ok": True }})
{ind}        return _finish(start_response, status, headers, body, method)
{ind}
{ind}    # Preflight OPTIONS
{ind}    if method == "OPTIONS" and path.startswith("/api/"):
{ind}        origin = environ.get("HTTP_ORIGIN")
{ind}        hdrs = [
{ind}            ("Content-Type", "application/json; charset=utf-8"),
{ind}            ("Access-Control-Allow-Methods", "GET,POST,OPTIONS"),
{ind}            ("Access-Control-Allow-Headers", "Content-Type, Accept, Authorization"),
{ind}            ("Access-Control-Max-Age", "86400"),
{ind}        ]
{ind}        if origin:
{ind}            hdrs += [
{ind}                ("Access-Control-Allow-Origin", origin),
{ind}                ("Vary", "Origin"),
{ind}                ("Access-Control-Allow-Credentials", "true"),
{ind}            ]
{ind}        start_response("204 No Content", hdrs)
{ind}        return [b""]
{ind}
{ind}    # Listado de notas (GET /api/notes)
{ind}    if path == "/api/notes" and method == "GET":
{ind}        try:
{ind}            from urllib.parse import parse_qs
{ind}            q = parse_qs(qs, keep_blank_values=True) if qs else {{}}
{ind}            lim = int((q.get("limit") or ["10"])[0] or "10")
{ind}            lim = lim if 1 <= lim <= 100 else 10
{ind}        except Exception:
{ind}            lim = 10
{ind}        code, payload, nxt = 200, None, None
{ind}        try:
{ind}            from sqlalchemy import text as _text
{ind}            with _engine().begin() as cx:
{ind}                rows = cx.execute(_text(
{ind}                    "SELECT id, text, title, url, summary, content, timestamp, expires_at, likes, views, reports, author_fp "
{ind}                    "FROM note ORDER BY timestamp DESC, id DESC LIMIT :lim"
{ind}                ), {{"lim": lim}}).mappings().all()
{ind}            items = [ _normalize_row(dict(r)) for r in rows ]  # type: ignore[name-defined]
{ind}            code, payload = 200, {{"ok": True, "items": items}}
{ind}        except Exception as e:
{ind}            code, payload = 500, {{"ok": False, "error": f"notes_query_failed: {{e}}" }}
{ind}        status, headers, body = _json(code, payload)
{ind}        extra = []
{ind}        try:
{ind}            # (opcional) encadenado next via Link/X-Next-Cursor si querés
{ind}            pass
{ind}        except Exception:
{ind}            pass
{ind}        return _finish(start_response, status, headers, body, method, extra_headers=extra)
{ind}
{ind}    # Publicar nota (POST /api/notes)
{ind}    if path == "/api/notes" and method == "POST":
{ind}        _code_payload, _data = _parse_post_note(environ)
{ind}        if _code_payload is not None:
{ind}            code, payload = _code_payload, _data
{ind}        else:
{ind}            try:
{ind}                code, payload = _insert_note(_data)
{ind}            except Exception as e:
{ind}                code, payload = 500, {{"ok": False, "error": str(e)}}
{ind}        status, headers, body = _json(code, payload)
{ind}        return _finish(start_response, status, headers, body, method)
{ind}
{ind}    # Acciones por id (POST /api/notes/<id>/like|view|report)
{ind}    if path.startswith("/api/notes/") and method == "POST":
{ind}        tail = path.removeprefix("/api/notes/")
{ind}        try:
{ind}            sid, action = tail.split("/", 1)
{ind}            note_id = int(sid)
{ind}        except Exception:
{ind}            note_id, action = None, ""
{ind}        if note_id and action in ("like","view","report"):
{ind}            try:
{ind}                from sqlalchemy import text as _text
{ind}                with _engine().begin() as cx:
{ind}                    # crea tabla/índices si faltan (idempotente)
{ind}                    cx.execute(_text("CREATE TABLE IF NOT EXISTS like_log (note_id INTEGER, action TEXT, ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP)"))
{ind}                    if action == "like":
{ind}                        cx.execute(_text("UPDATE note SET likes = COALESCE(likes,0)+1 WHERE id=:i"), {{"i": note_id}})
{ind}                    elif action == "view":
{ind}                        cx.execute(_text("UPDATE note SET views = COALESCE(views,0)+1 WHERE id=:i"), {{"i": note_id}})
{ind}                    else:
{ind}                        cx.execute(_text("UPDATE note SET reports = COALESCE(reports,0)+1 WHERE id=:i"), {{"i": note_id}})
{ind}                    cx.execute(_text("INSERT INTO like_log(note_id, action) VALUES(:i,:a)"), {{"i": note_id, "a": action}})
{ind}                code, payload = 200, {{"ok": True, "id": note_id}}
{ind}            except Exception as e:
{ind}                code, payload = 500, {{"ok": False, "error": str(e)}}
{ind}            status, headers, body = _json(code, payload)
{ind}            return _finish(start_response, status, headers, body, method)
{ind}
{ind}    # 404
{ind}    if path.startswith("/api/"):
{ind}        status, headers, body = _json(404, {{"ok": False, "error": "not_found"}})
{ind}    else:
{ind}        status, headers, body = _html(404, "<h1>Not found</h1>")
{ind}    return _finish(start_response, status, headers, body, method)
"""
    )

    new_lines = lines[:hdr_idx] + body.split("\n") + lines[end_idx:]
    return "\n".join(new_lines)

changed = False

# 1) _finish canónico
src, _ = ensure_finish(src); changed = True

# 2) helper single-attr (si falta)
src, _ = ensure_helper_single_attr(src); changed = True

# 3) _app canónico
try:
    src = replace_app_body(src); changed = True
except Exception as e:
    print("✗ no pude reemplazar _app:", e); sys.exit(1)

# 4) Escribir
put(src)

# 5) Compilar y mostrar contexto si algo falla
try:
    py_compile.compile(str(W), doraise=True)
    print("✓ backend saneado (_finish + _app) | backup=", bak.name)
except Exception as e:
    print("✗ py_compile FAIL:", e)
    tb = traceback.format_exc()
    m = re.search(r'__init__\.py, line (\d+)', tb)
    if m:
        ln = int(m.group(1))
        ctx = src.splitlines()
        a = max(1, ln-25); b = min(len(ctx), ln+25)
        print(f"\n--- Contexto {a}-{b} ---")
        for i in range(a, b+1):
            print(f"{i:5d}: {ctx[i-1]}")
    sys.exit(1)
