#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile

P = pathlib.Path("wsgiapp/__init__.py")
s = P.read_text(encoding="utf-8")
bak = P.with_suffix(".py.bak_actions")
changed = False

# Anclas: el bloque problemático empieza en este if POST y termina antes del if GET
start_re = re.compile(r'^(\s*)if\s+path\.startswith\("/api/notes/"\)\s+and\s+method\s*==\s*"POST":\s*$', re.M)
end_re   = re.compile(r'^\s*if\s+path\.startswith\("/api/notes/"\)\s+and\s+method\s*==\s*"GET":\s*$', re.M)

m = start_re.search(s)
n = end_re.search(s)
if not m or not n or n.start() <= m.start():
    print("No pude localizar el bloque POST /api/notes/... a reemplazar; abortando.")
    sys.exit(2)

indent = m.group(1)
new_block = f"""{indent}if path.startswith("/api/notes/") and method == "POST":
{indent}    tail = path.removeprefix("/api/notes/")
{indent}    try:
{indent}        sid, action = tail.split("/", 1)
{indent}        note_id = int(sid)
{indent}    except Exception:
{indent}        note_id = None
{indent}        action = ""
{indent}    if note_id:
{indent}        if action == "like":
{indent}            # Like con dedupe 1×persona (log + índice único)
{indent}            try:
{indent}                from sqlalchemy import text as _text
{indent}                with _engine().begin() as cx:
{indent}                    # Tabla e índice (no-op si existen)
{indent}                    try:
{indent}                        cx.execute(_text(\"\"\"\n{indent}                            CREATE TABLE IF NOT EXISTS like_log(\n{indent}                                id SERIAL PRIMARY KEY,\n{indent}                                note_id INTEGER NOT NULL REFERENCES note(id) ON DELETE CASCADE,\n{indent}                                fingerprint VARCHAR(128) NOT NULL,\n{indent}                                created_at TIMESTAMPTZ DEFAULT NOW()\n{indent}                            )\n{indent}                        \"\"\"))\n{indent}                        cx.execute(_text(\"\"\"\n{indent}                            CREATE UNIQUE INDEX IF NOT EXISTS uq_like_note_fp\n{indent}                            ON like_log(note_id, fingerprint)\n{indent}                        \"\"\"))\n{indent}                    except Exception:\n{indent}                        pass\n{indent}                    fp = _fingerprint(environ)\n{indent}                    inserted = False\n{indent}                    try:\n{indent}                        cx.execute(_text(\n{indent}                            "INSERT INTO like_log(note_id, fingerprint, created_at) VALUES (:id,:fp, NOW())"\n{indent}                        ), {{"id": note_id, "fp": fp}})\n{indent}                        inserted = True\n{indent}                    except Exception:\n{indent}                        inserted = False\n{indent}                    if inserted:\n{indent}                        cx.execute(_text(\n{indent}                            "UPDATE note SET likes = COALESCE(likes,0)+1 WHERE id=:id"\n{indent}                        ), {{"id": note_id}})\n{indent}                    row = cx.execute(_text(\n{indent}                        "SELECT COALESCE(likes,0), COALESCE(views,0), COALESCE(reports,0) FROM note WHERE id=:id"\n{indent}                    ), {{"id": note_id}}).first()\n{indent}                    likes  = int(row[0] or 0)\n{indent}                    views  = int(row[1] or 0)\n{indent}                    reports= int(row[2] or 0)\n{indent}                code, payload = 200, {{\"ok\": True, \"id\": note_id, \"likes\": likes, \"views\": views, \"reports\": reports, \"deduped\": (not inserted)}}\n{indent}            except Exception as e:\n{indent}                code, payload = 500, {{\"ok\": False, \"error\": str(e)}}\n{indent}        elif action == "view":\n{indent}            code, payload = _inc_simple(note_id, "views")\n{indent}        elif action == "report":\n{indent}            try:\n{indent}                import os\n{indent}                threshold = int(os.environ.get("REPORT_THRESHOLD", "5") or "5")\n{indent}            except Exception:\n{indent}                threshold = 5\n{indent}            fp = _fingerprint(environ)\n{indent}            try:\n{indent}                code, payload = _report_once(note_id, fp, threshold)\n{indent}            except Exception as e:\n{indent}                code, payload = 500, {{\"ok\": False, \"error\": f\"report_failed: {{e}}\"}}\n{indent}        else:\n{indent}            code, payload = 404, {{\"ok\": False, \"error\": "unknown_action"}}\n{indent}        status, headers, body = _json(code, payload)\n{indent}        return _finish(start_response, status, headers, body, method)\n"""

s2 = s[:m.start()] + new_block + s[n.start():]
if not bak.exists():
    shutil.copyfile(P, bak)
P.write_text(s2, encoding="utf-8")

# Validación de compilación
try:
    py_compile.compile(str(P), doraise=True)
    print("patched: bloque POST /api/notes/<id>/<action> reconstruido (backup creado)")
except Exception as e:
    print("✗ py_compile aún falla:", e)
    sys.exit(2)
