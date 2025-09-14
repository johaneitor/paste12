#!/usr/bin/env python3
import re, sys, pathlib

p = pathlib.Path("wsgiapp/__init__.py")
s = p.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n")

changed = False

def inject_guard(block, verb):
    """
    Inserta un early-guard 404 si no existe el id antes del UPDATE del endpoint /api/notes/<id>/{verb}
    Se busca la función del endpoint por palabra clave y se inyecta el guard al inicio.
    """
    rx = re.compile(rf"(?ms)(def\s+[a-zA-Z_][\w]*\s*\([^)]*\):\s*\n)([^\n]*?/api/notes.*?{verb}.*?\n)((?:\s+.*\n)+?)")
    m = rx.search(block)
    if not m:
        return block, False
    head, route_line, body = m.groups()

    # Ya tiene guard?
    if "not_found" in body and "SELECT 1 FROM note" in body:
        return block, False

    guard = (
        "    # guardia 404 si id no existe\n"
        "    try:\n"
        "        cur = db.cursor()\n"
        "        cur.execute('SELECT 1 FROM note WHERE id=%s', (note_id,))\n"
        "        row = cur.fetchone()\n"
        "        cur.close()\n"
        "        if not row:\n"
        "            return _json({'ok': False, 'error': 'not_found'}, status='404 Not Found')\n"
        "    except Exception:\n"
        "        try:\n"
        "            db.rollback()\n"
        "        except Exception:\n"
        "            pass\n"
        "        return _json({'ok': False, 'error': 'db_error'}, status='500 Internal Server Error')\n\n"
    )

    new = head + route_line + guard + body
    return new, True

# Inyecta en like/view/report si aparecen
s2 = s
for verb in ("like", "view", "report"):
    s2, did = inject_guard(s2, verb)
    changed = changed or did

if not changed:
    print("Nada que parchear (no se halló patrón de endpoints like/view/report o ya tienen guard).")
    sys.exit(0)

p.write_text(s2, encoding="utf-8")
print("OK: guard 404 inyectado en like/view/report (cuando aplica).")
