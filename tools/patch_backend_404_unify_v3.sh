#!/usr/bin/env bash
set -euo pipefail

python - <<'PY'
import io, re, py_compile, shutil, time
from pathlib import Path

P = Path("wsgiapp/__init__.py")
S = P.read_text(encoding="utf-8")
TS = time.strftime("%Y%m%d-%H%M%SZ")

def ensure_import(s, mod):
    return (f"import {mod}\n"+s) if re.search(rf'^\s*import\s+{mod}\b', s, re.M) is None else s

for m in ("json","sqlite3","re","os"):
    S = ensure_import(S, m)

helper = '''
# --- paste12: helper único para contadores con 404 limpio ---
def _p12_bump_counter(note_id, field):
    # Obtiene conexión; adaptá si tu app usa otro mecanismo
    conn = globals().get('DB') or globals().get('db')
    if conn is None and 'get_db' in globals():
        try:
            conn = get_db()
        except Exception:
            conn = None
    if conn is None:
        try:
            import sqlite3 as _sq
            conn = _sq.connect('data.sqlite3')
        except Exception:
            conn = None
    if conn is None:
        body = json.dumps({"error":"server_db_unavailable"})
        return (body, 500, {"Content-Type":"application/json"})

    if field not in ("likes","views","reports"):
        body = json.dumps({"error":"bad_field"})
        return (body, 400, {"Content-Type":"application/json"})

    sql = f"UPDATE notes SET {field}={field}+1 WHERE id=? RETURNING {field}"
    try:
        cur = conn.execute(sql, (note_id,))
        row = cur.fetchone()
        if row is None:
            body = json.dumps({"error":"not_found"})
            return (body, 404, {"Content-Type":"application/json"})
        conn.commit()
        return (json.dumps({"ok": True, field: row[0]}), 200, {"Content-Type":"application/json"})
    except Exception:
        # Fallback para SQLite sin RETURNING
        try:
            cur = conn.execute(f"UPDATE notes SET {field}={field}+1 WHERE id=?", (note_id,))
            if getattr(cur, "rowcount", 0) == 0:
                body = json.dumps({"error":"not_found"})
                return (body, 404, {"Content-Type":"application/json"})
            conn.commit()
            return (json.dumps({"ok": True}), 200, {"Content-Type":"application/json"})
        except Exception:
            body = json.dumps({"error":"server_error"})
            return (body, 500, {"Content-Type":"application/json"})
'''

# Asegurar helper al final del archivo si no está
if "_p12_bump_counter(" not in S:
    S = S.rstrip() + "\n\n" + helper

# Estrategia simple y robusta: volvemos a definir los endpoints al FINAL,
# así estas versiones prevalecen sobre cualquier duplicado previo.
endpoints = '''
def like(note_id):
    return _p12_bump_counter(note_id, "likes")

def view(note_id):
    return _p12_bump_counter(note_id, "views")

def report(note_id):
    return _p12_bump_counter(note_id, "reports")
'''
S = S.rstrip() + "\n\n" + endpoints + "\n"

# Backup + escribir + compilar (regla del proyecto)
bak = P.with_name(f"__init__.py.bak-{TS}")
shutil.copy2(P, bak)
P.write_text(S, encoding="utf-8")
py_compile.compile(str(P), doraise=True)
print("PATCH_OK:", bak.name)
PY

git add wsgiapp/__init__.py wsgiapp/__init__.py.bak-* || true
git commit -m "BE: unify like/view/report via _p12_bump_counter; 404 en not_found [p12]" || true
