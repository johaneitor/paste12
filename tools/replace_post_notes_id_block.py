#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)

def rw():
    return W.read_text(encoding="utf-8")

def norm(s: str) -> str:
    s = s.replace("\r\n","\n").replace("\r","\n")
    if "\t" in s: s = s.replace("\t","    ")
    return s

def indw(line: str) -> int:
    return len(line) - len(line.lstrip(" "))

def gate():
    try:
        py_compile.compile(str(W), doraise=True)
        print("✓ py_compile OK"); return True
    except Exception as e:
        print("✗ py_compile FAIL:", e)
        tb = traceback.format_exc()
        m = re.search(r'__init__\.py, line (\d+)', tb)
        if m:
            ln = int(m.group(1))
            ctx = rw().splitlines()
            a = max(1, ln-40); b = min(len(ctx), ln+40)
            print(f"\n--- Ventana {a}-{b} ---")
            for k in range(a, b+1):
                print(f"{k:5d}: {ctx[k-1]}")
        return False

s = norm(rw())
lines = s.split("\n")

# Anchors para el bloque POST y el siguiente GET
pat_post = re.compile(r'^([ ]*)if\s+path\.startswith\(\s*[\'"]/api/notes/[\'"]\s*\)\s+and\s+method\s*==\s*[\'"]POST[\'"]\s*:\s*$', re.M)
pat_get  = re.compile(r'^[ ]*if\s+path\.startswith\(\s*[\'"]/api/notes/[\'"]\s*\)\s+and\s+method\s*==\s*[\'"]GET[\'"]\s*:\s*$', re.M)

mp = pat_post.search(s)
if not mp:
    print("✗ no encontré el bloque POST /api/notes/:id"); sys.exit(1)

post_indent_ws = mp.group(1)
post_indent = len(post_indent_ws)
start = mp.start()

mg = pat_get.search(s, mp.end())
if mg:
    end = mg.start()
else:
    # fallback: hasta antes de inner_app / fin de archivo
    m2 = re.search(r'^[ ]*if\s+inner_app\s+is\s+not\s+None\s*:\s*$', s[mp.end():], re.M)
    end = mp.end() + (m2.start() if m2 else (len(s) - mp.end()))

# Template canónica del handler POST
tmpl = f"""{post_indent_ws}if path.startswith("/api/notes/") and method == "POST":
{post_indent_ws}    tail = path.removeprefix("/api/notes/")
{post_indent_ws}    try:
{post_indent_ws}        sid, action = tail.split("/", 1)
{post_indent_ws}        note_id = int(sid)
{post_indent_ws}    except Exception:
{post_indent_ws}        note_id = None
{post_indent_ws}        action = ""
{post_indent_ws}    if note_id:
{post_indent_ws}        if action == "like":
{post_indent_ws}            try:
{post_indent_ws}                from sqlalchemy import text as _text
{post_indent_ws}                with _engine().begin() as cx:  # type: ignore[name-defined]
{post_indent_ws}                    # DDL idempotente (tabla e índice)
{post_indent_ws}                    cx.execute(_text(\"\"\"CREATE TABLE IF NOT EXISTS like_log(
{post_indent_ws}                        note_id INTEGER NOT NULL REFERENCES note(id) ON DELETE CASCADE,
{post_indent_ws}                        fingerprint VARCHAR(128) NOT NULL,
{post_indent_ws}                        created_at TIMESTAMPTZ DEFAULT NOW(),
{post_indent_ws}                        PRIMARY KEY (note_id, fingerprint)
{post_indent_ws}                    )\"\"\"))
{post_indent_ws}                    cx.execute(_text(\"\"\"CREATE UNIQUE INDEX IF NOT EXISTS uq_like_note_fp
{post_indent_ws}                        ON like_log(note_id, fingerprint)\"\"\"))
{post_indent_ws}                    # Inserción deduplicada
{post_indent_ws}                    fp = _fingerprint(environ)  # type: ignore[name-defined]
{post_indent_ws}                    inserted = False
{post_indent_ws}                    try:
{post_indent_ws}                        cx.execute(_text(
{post_indent_ws}                            "INSERT INTO like_log(note_id, fingerprint, created_at) VALUES (:id,:fp, NOW())"
{post_indent_ws}                        ), {{"id": note_id, "fp": fp}})
{post_indent_ws}                        inserted = True
{post_indent_ws}                    except Exception:
{post_indent_ws}                        inserted = False
{post_indent_ws}                    if inserted:
{post_indent_ws}                        cx.execute(_text(
{post_indent_ws}                            "UPDATE note SET likes = COALESCE(likes,0)+1 WHERE id=:id"
{post_indent_ws}                        ), {{"id": note_id}})
{post_indent_ws}                    row = cx.execute(_text(
{post_indent_ws}                        "SELECT COALESCE(likes,0), COALESCE(views,0), COALESCE(reports,0) FROM note WHERE id=:id"
{post_indent_ws}                    ), {{"id": note_id}}).first()
{post_indent_ws}                    likes   = int(row[0] or 0)
{post_indent_ws}                    views   = int(row[1] or 0)
{post_indent_ws}                    reports = int(row[2] or 0)
{post_indent_ws}                code, payload = 200, {{"ok": True, "id": note_id, "likes": likes, "views": views, "reports": reports, "deduped": (not inserted)}}
{post_indent_ws}            except Exception as e:
{post_indent_ws}                code, payload = 500, {{"ok": False, "error": f"like_failed: {{e}}" }}
{post_indent_ws}        elif action == "view":
{post_indent_ws}            code, payload = _inc_simple(note_id, "views")  # type: ignore[name-defined]
{post_indent_ws}        elif action == "report":
{post_indent_ws}            try:
{post_indent_ws}                import os
{post_indent_ws}                threshold = int(os.environ.get("REPORT_THRESHOLD", "5") or "5")
{post_indent_ws}            except Exception:
{post_indent_ws}                threshold = 5
{post_indent_ws}            fp = _fingerprint(environ)  # type: ignore[name-defined]
{post_indent_ws}            try:
{post_indent_ws}                code, payload = _report_once(note_id, fp, threshold)  # type: ignore[name-defined]
{post_indent_ws}            except Exception as e:
{post_indent_ws}                code, payload = 500, {{"ok": False, "error": f"report_failed: {{e}}" }}
{post_indent_ws}        else:
{post_indent_ws}            code, payload = 404, {{"ok": False, "error": "unknown_action"}}
{post_indent_ws}        status, headers, body = _json(code, payload)  # type: ignore[name-defined]
{post_indent_ws}        return _finish(start_response, status, headers, body, method)  # type: ignore[name-defined]
"""

new_s = s[:start] + tmpl + s[end:]
if new_s == s:
    print("OK: no cambios aplicados")
    sys.exit(0)

bak = W.with_suffix(".py.replace_post_notes_block.bak")
if not bak.exists():
    shutil.copyfile(W, bak)
W.write_text(new_s, encoding="utf-8")
print(f"patched: bloque POST /api/notes/:id reemplazado | backup={bak.name}")

if not gate():
    sys.exit(1)
