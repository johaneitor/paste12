#!/usr/bin/env bash
set -euo pipefail

python - <<'PY'
import io,re,py_compile,shutil,time
from pathlib import Path

P=Path("wsgiapp/__init__.py"); S=P.read_text(encoding="utf-8")
TS=time.strftime("%Y%m%d-%H%M%SZ")

def ensure_imports(s):
    need=[]
    for mod in ("json","sqlite3","re","os"):
        if re.search(rf'^\s*import\s+{mod}\b', s, re.M) is None:
            need.append(f"import {mod}")
    return ("\n".join(need)+"\n"+s) if need else s

def upsert_helper(s):
    # helper multilínea, NUNCA en una sola línea
    helper = r"""
# --- paste12: helper único para contadores con 404 limpio ---
def _p12_bump_counter(note_id, field):
    """
    Helper que incrementa un campo y devuelve 200; si la nota no existe -> 404.
    Usa UPDATE ... RETURNING cuando está disponible (SQLite 3.35+).
    """
    # obtener conexión (adaptá si tu app usa otro módulo)
    conn = globals().get('DB') or globals().get('db') or None
    if conn is None and 'get_db' in globals():
        try:
            conn = get_db()
        except Exception:
            conn = None
    if conn is None:
        # último recurso: sqlite3 en archivo local por convención (si aplica)
        try:
            conn = sqlite3.connect('data.sqlite3')
        except Exception:
            pass

    if conn is None:
        body = json.dumps({"error":"server_db_unavailable"})
        return (body, 500, {"Content-Type":"application/json"})

    # proteger nombre de columna
    if field not in ("likes","views","reports"):
        body = json.dumps({"error":"bad_field"})
        return (body, 400, {"Content-Type":"application/json"})

    sql = f"UPDATE notes SET {field}={field}+1 WHERE id=? RETURNING {field}"
    cur = None
    try:
        cur = conn.execute(sql, (note_id,))
        row = cur.fetchone()
        if row is None:
            body = json.dumps({"error":"not_found"})
            return (body, 404, {"Content-Type":"application/json"})
        conn.commit()
        return (json.dumps({"ok": True, field: row[0]}), 200, {"Content-Type":"application/json"})
    except Exception as e:
        # fallback para SQLite viejo (sin RETURNING)
        try:
            cur = conn.execute(f"UPDATE notes SET {field}={field}+1 WHERE id=?", (note_id,))
            if cur.rowcount == 0:
                body = json.dumps({"error":"not_found"})
                return (body, 404, {"Content-Type":"application/json"})
            conn.commit()
            # no sabemos el valor exacto sin SELECT; devolvemos ok
            return (json.dumps({"ok": True}), 200, {"Content-Type":"application/json"})
        except Exception:
            body = json.dumps({"error":"server_error"})
            return (body, 500, {"Content-Type":"application/json"})
"""
    if "_p12_bump_counter(" not in s:
        s += "\n"+helper
    return s

def replace_endpoint(s, fn, field):
    # Reemplaza cuerpo de def <fn>(note_id): para delegar SOLO al helper.
    pat = re.compile(rf'(?ms)^\s*def\s+{fn}\(note_id\):\s*(.*?)^(?=\s*def\s+\w+\(|\Z)')
    m = list(pat.finditer(s))
    if not m:
        # si no existe, agregamos una versión mínima
        block = f"""
def {fn}(note_id):
    return _p12_bump_counter(note_id, "{field}")
"""
        return s + "\n" + block
    # manteniendo firma, sustituir el cuerpo
    start,end = m[-1].start(), m[-1].end()
    new = f"""
def {fn}(note_id):
    return _p12_bump_counter(note_id, "{field}")
"""
    return s[:start] + new + s[end:]

S = ensure_imports(S)
S = upsert_helper(S)
S = replace_endpoint(S, "like",   "likes")
S = replace_endpoint(S, "view",   "views")
S = replace_endpoint(S, "report", "reports")

# backup y escribir
bak=P.with_name(f"__init__.py.bak-{TS}")
shutil.copy2(P, bak)
P.write_text(S, encoding="utf-8")
py_compile.compile(str(P), doraise=True)
print("PATCH_OK:", bak.name)
PY

git add wsgiapp/__init__.py wsgiapp/__init__.py.bak-* || true
git commit -m "BE: unify like/view/report via _p12_bump_counter + 404 not_found [p12]" || true
