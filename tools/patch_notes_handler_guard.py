#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)

src = W.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n")

# Localiza el bloque GET/HEAD de /api/notes y /api/notes_fallback
pat = re.compile(
    r'(?m)^([ ]*)if[ ]+path[ ]+in[ ]*\(\s*[\'"]/api/notes[\'"]\s*,\s*[\'"]/api/notes_fallback[\'"]\s*\)\s*'
    r'and\s*method\s*in\s*\(\s*[\'"]GET[\'"]\s*,\s*[\'"]HEAD[\'"]\s*\)\s*:\s*$'
)

m = pat.search(src)
if not m:
    print("✗ no encontré el handler de GET /api/notes"); sys.exit(1)

base_ws = m.group(1)
start = m.end()

# Fin del bloque: primera línea no vacía con indent <= indent base
lines = src.split("\n")
start_idx = src[:start].count("\n")
end_idx = len(lines)
for j in range(start_idx+1, len(lines)):
    L = lines[j]
    if L.strip() and (len(L) - len(L.lstrip(" "))) <= len(base_ws):
        end_idx = j
        break

guarded = f"""{base_ws}if path in ("/api/notes", "/api/notes_fallback") and method in ("GET","HEAD"):
{base_ws}    try:
{base_ws}        # Camino normal
{base_ws}        code, payload, nxt = _notes_query(qs)  # type: ignore[name-defined]
{base_ws}    except Exception as e:
{base_ws}        # Fallback SQL simple para no romper el frontend si falla _notes_query
{base_ws}        try:
{base_ws}            from sqlalchemy import text as _text
{base_ws}            from urllib.parse import parse_qs as _parse_qs
{base_ws}            _q = _parse_qs(qs or "", keep_blank_values=True)
{base_ws}            try:
{base_ws}                lim = int((_q.get("limit", [20]) or [20])[0] or 20)
{base_ws}            except Exception:
{base_ws}                lim = 20
{base_ws}            if lim < 1: lim = 1
{base_ws}            if lim > 100: lim = 100
{base_ws}            with _engine().begin() as cx:  # type: ignore[name-defined]
{base_ws}                rows = cx.execute(_text(
{base_ws}                    "SELECT id, text, title, url, summary, content, timestamp, expires_at, likes, views, reports, author_fp "
{base_ws}                    "FROM note ORDER BY timestamp DESC, id DESC LIMIT :lim"
{base_ws}                ), {{"lim": lim}}).mappings().all()
{base_ws}            items = [ _normalize_row(dict(r)) for r in rows ]  # type: ignore[name-defined]
{base_ws}            code, payload, nxt = 200, {{"ok": True, "items": items}}, None
{base_ws}        except Exception as e2:
{base_ws}            code, payload, nxt = 500, {{"ok": False, "error": f"notes_query_failed: {{e}}; fallback_failed: {{e2}}"}}, None
{base_ws}    status, headers, body = _json(code, payload)  # type: ignore[name-defined]
{base_ws}    extra = []
{base_ws}    try:
{base_ws}        if nxt and nxt.get("cursor_ts") and nxt.get("cursor_id"):
{base_ws}            from urllib.parse import quote
{base_ws}            ts_q = quote(str(nxt["cursor_ts"]), safe="")
{base_ws}            link = f'</api/notes?cursor_ts={{ts_q}}&cursor_id={{nxt["cursor_id"]}}>; rel="next"'
{base_ws}            extra.append(("Link", link))
{base_ws}            extra.append(("X-Next-Cursor", json.dumps(nxt)))
{base_ws}    except Exception:
{base_ws}        pass
{base_ws}    return _finish(start_response, status, headers, body, method, extra_headers=extra)  # type: ignore[name-defined]
"""

new_src = "\n".join(lines[:start_idx]) + "\n" + guarded.rstrip("\n") + "\n" + "\n".join(lines[end_idx:])
if new_src == src:
    print("OK: no hubo cambios"); sys.exit(0)

bak = W.with_suffix(".py.notes_guard.bak")
if not bak.exists():
    shutil.copyfile(W, bak)
W.write_text(new_src, encoding="utf-8")
print(f"patched: handler /api/notes con try/fallback | backup={bak.name}")

# Gate
py_compile.compile(str(W), doraise=True)
print("✓ py_compile OK")
