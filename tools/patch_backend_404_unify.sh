#!/usr/bin/env bash
set -euo pipefail
# Restaurar base limpia (por si hubo indent roto)
git fetch origin main
git checkout -q origin/main -- wsgiapp/__init__.py || true

python - <<'PY'
import re, py_compile
p="wsgiapp/__init__.py"
s=open(p,"r",encoding="utf-8").read()

helper = r'''
def _p12_bump_counter(conn, note_id:int, field:str):
    assert field in ("likes","views","reports")
    cur = conn.execute('SELECT id, likes, views, reports FROM notes WHERE id=?', (note_id,))
    row = cur.fetchone()
    if row is None:
        return None
    conn.execute(f'UPDATE notes SET {field}={field}+1 WHERE id=?', (note_id,))
    cur = conn.execute('SELECT id, likes, views, reports FROM notes WHERE id=?', (note_id,))
    row = cur.fetchone()
    return {"id": row[0], "likes": row[1], "views": row[2], "reports": row[3]}
'''
if "_p12_bump_counter(" not in s:
    s += "\n" + helper

# imports mínimos
if "import sqlite3" not in s: s = "import sqlite3\n"+s
if "import json" not in s: s = "import json\n"+s

def patch_route(s,name,field):
    pat = re.compile(rf'(def\\s+{name}\\s*\\(.*?\\):)(.*?)(?=\\ndef\\s|\\Z)', re.S)
    repl = rf"""\\1
    conn = sqlite3.connect("data.sqlite3")
    try:
        row = _p12_bump_counter(conn, int(note_id), "{field}")
    finally:
        conn.close()
    if row is None:
        from werkzeug.exceptions import NotFound
        raise NotFound()
    return (json.dumps(row), 200, {{"Content-Type":"application/json"}})
"""
    if pat.search(s):
        return pat.sub(repl, s, count=1)
    s += f"""
def {name}(note_id):
    conn = sqlite3.connect("data.sqlite3")
    try:
        row = _p12_bump_counter(conn, int(note_id), "{field}")
    finally:
        conn.close()
    if row is None:
        from werkzeug.exceptions import NotFound
        raise NotFound()
    return (json.dumps(row), 200, {{"Content-Type":"application/json"}})
"""
    return s

for nm, fld in (("like","likes"),("view","views"),("report","reports")):
    s = patch_route(s, nm, fld)

open(p,"w",encoding="utf-8").write(s)
py_compile.compile(p, doraise=True)
print("PATCH_OK")
PY

git add wsgiapp/__init__.py
git commit -m "paste12: 404 limpios en like/view/report con helper único"
git push
