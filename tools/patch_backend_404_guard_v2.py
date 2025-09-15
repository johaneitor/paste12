#!/usr/bin/env python3
import re, sys, pathlib

W = pathlib.Path("wsgiapp/__init__.py")
src = W.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n")

def inject_guard_for(verb, s):
    """
    Inserta, inmediatamente después de la condición del endpoint POST /api/notes/<id>/{verb},
    un guard SELECT 1 ... que devuelve 404 si no existe el id. Idempotente.
    """
    # localiza una línea tipo: if ... POST ... "/api/notes" ... {verb} ...:
    # es deliberadamente flexible y sólo actúa una vez por endpoint
    pat = re.compile(
        rf'(?m)^([ \t]*(?:if|elif)[^\n]*POST[^\n]*?/api/notes[^\n]*?{verb}[^\n]*:\s*\n)'
    )

    def _add_guard(m):
        head = m.group(1)
        # Detecta indent del bloque (la condición) y arma indent del cuerpo (+4 espacios)
        base_indent = re.match(r'^([ \t]*)', head).group(1)
        body_indent = base_indent + "    "
        guard = (
            f"{head}"
            f"{body_indent}# guard 404: si no existe el id, evitamos 500 y abortos transaccionales\n"
            f"{body_indent}try:\n"
            f"{body_indent}    cur = db.cursor()\n"
            f"{body_indent}    cur.execute('SELECT 1 FROM note WHERE id=%s', (note_id,))\n"
            f"{body_indent}    row = cur.fetchone()\n"
            f"{body_indent}    cur.close()\n"
            f"{body_indent}    if not row:\n"
            f"{body_indent}        try: db.rollback()\n"
            f"{body_indent}        except Exception: pass\n"
            f"{body_indent}        return _json({{'ok': False, 'error': 'not_found'}}, status='404 Not Found')\n"
            f"{body_indent}except Exception:\n"
            f"{body_indent}    try: db.rollback()\n"
            f"{body_indent}    except Exception: pass\n"
            f"{body_indent}    return _json({{'ok': False, 'error': 'db_error'}}, status='500 Internal Server Error')\n"
        )
        return guard

    # idempotencia: si ya hay SELECT 1 guard en este endpoint, salta
    already = re.compile(
        rf'(?m)^(?:[ \t]*)# guard 404.*?\n(?:[ \t]*)cur\.execute\(\'SELECT 1 FROM note WHERE id=%s\'',
        re.DOTALL
    )
    # si ya existe, no toca
    if already.search(src):
        return s, False
    new_s, n = pat.subn(_add_guard, s, count=1)
    return new_s, n > 0

changed = False
for v in ("like", "report"):
    src, did = inject_guard_for(v, src)
    changed = changed or did

if not changed:
    print("Nada que parchear (no se encontró patrón o ya había guard).")
    sys.exit(0)

W.write_text(src, encoding="utf-8")
print("OK: guard 404 inyectado para like/report.")
