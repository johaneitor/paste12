#!/usr/bin/env python3
import re, sys, pathlib

W = pathlib.Path("wsgiapp/__init__.py")
src = W.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n")

# No dupliques si ya existe el guard
if "p12_pre_guard_like_view_report" in src:
    print("Guard ya presente, nada que hacer.")
    sys.exit(0)

# Buscamos un lugar seguro para inyectar: luego de tener method/path y conexión db preparada.
# Patrón común: asignación de path y method cerca del inicio del handler.
m = re.search(r'(?m)^\s*path\s*=\s*environ\.get\(\s*"PATH_INFO"\s*,\s*"/"\s*\)\s*.*\n', src)
m2 = re.search(r'(?m)^\s*method\s*=\s*environ\.get\(\s*"REQUEST_METHOD"\s*,\s*"GET"\s*\)\s*.*\n', src)

if not (m and m2):
    print("No encontré asignaciones de path/method canónicas. Abortando para no romper.")
    sys.exit(0)

insertion_point = max(m.end(), m2.end())

guard = """
    # p12_pre_guard_like_view_report — early 404 si el note_id no existe en POST /api/notes/<id>/(like|view|report)
    try:
        _p12_m = method
        _p12_p = path
    except NameError:
        _p12_m = environ.get("REQUEST_METHOD", "GET")
        _p12_p = environ.get("PATH_INFO", "/")
    if _p12_m == "POST":
        import re as _re
        _m = _re.match(r"^/api/notes/(\\d+)/(like|view|report)$", _p12_p or "")
        if _m:
            try:
                _note_id = int(_m.group(1))
                cur = db.cursor()
                cur.execute("SELECT 1 FROM note WHERE id=%s", (_note_id,))
                _row = cur.fetchone()
                cur.close()
                if not _row:
                    return _json({"ok": False, "error": "not_found"}, status="404 Not Found")
            except Exception:
                try:
                    db.rollback()
                except Exception:
                    pass
                return _json({"ok": False, "error": "db_error"}, status="500 Internal Server Error")
"""

new_src = src[:insertion_point] + guard + src[insertion_point:]
W.write_text(new_src, encoding="utf-8")
print("OK: pre-guard like/view/report inyectado.")
