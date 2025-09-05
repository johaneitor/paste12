#!/usr/bin/env python3
import pathlib, re, sys, shutil, py_compile

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("ERROR: wsgiapp/__init__.py no existe"); sys.exit(2)

raw = W.read_text(encoding="utf-8")
s = raw.replace("\r\n","\n").replace("\r","\n").replace("\t","    ")

changed = (s != raw)

# ---------- 1) Normalizar/eliminar definiciones rotas/duplicadas del helper ----------
# Eliminamos TODAS las defs de _json_passthrough_like (bien o mal indentadas) escaneando por bloques.
lines = s.split("\n")
out = []
i = 0
removed_helpers = 0
def_line_re = re.compile(r'^([ ]*)def\s+_json_passthrough_like\s*\([^)]*\)\s*:\s*(?:#.*)?$')

while i < len(lines):
    m = def_line_re.match(lines[i])
    if not m:
        out.append(lines[i]); i += 1
        continue
    base_indent = len(m.group(1))
    j = i + 1
    # avanzar hasta el fin del bloque de la función
    while j < len(lines):
        line = lines[j]
        # fin del bloque si encontramos una línea con indent <= base y no vacía
        if line.strip() != "" and (len(line) - len(line.lstrip(" ")) <= base_indent):
            break
        j += 1
    # drop i..j-1
    removed_helpers += 1
    i = j

s = "\n".join(out)

# ---------- 2) Asegurar una ÚNICA implementación top-level sana del helper ----------
helper = '''
def _json_passthrough_like(note_id: int):
    """
    Helper estable (sólo suma 1 a likes y devuelve payload). La dedupe 1×persona
    se aplica fuera (guard del endpoint). Si no existe la nota => 404.
    """
    try:
        from sqlalchemy import text as _text
        with _engine().begin() as cx:
            cx.execute(
                _text("UPDATE note SET likes = COALESCE(likes,0)+1 WHERE id=:id"),
                {"id": note_id}
            )
            row = cx.execute(
                _text("SELECT id, COALESCE(likes,0) AS likes, COALESCE(views,0) AS views, COALESCE(reports,0) AS reports FROM note WHERE id=:id"),
                {"id": note_id}
            ).mappings().first()
        if not row:
            return 404, {"ok": False, "error": "not_found"}
        return 200, {"ok": True, "id": row["id"], "likes": row["likes"], "views": row["views"], "reports": row["reports"]}
    except Exception as e:
        return 500, {"ok": False, "error": str(e)}
'''.lstrip("\n")

# Insertar al final si no existe (ya borramos todas)
if not re.search(r'(?m)^def\s+_json_passthrough_like\s*\(', s):
    if not s.endswith("\n"):
        s += "\n"
    s += "\n" + helper
    changed = True

# ---------- 3) Reparar el bloque POST /api/notes/:id/* de forma canónica ----------
# Reemplazamos de 'if path.startswith("/api/notes/") and method == "POST":' hasta
# el inicio del siguiente gran bloque (GET /api/notes/) o un guardado obvio.
post_re = re.compile(r'(?m)^([ ]*)if\s+path\.startswith\("/api/notes/"\)\s+and\s+method\s*==\s*"POST":\s*$')
get_re  = re.compile(r'(?m)^([ ]*)if\s+path\.startswith\("/api/notes/"\)\s+and\s+method\s*==\s*"GET":\s*$')

post_m = post_re.search(s)
if post_m:
    indent = post_m.group(1)
    start = post_m.start()
    # buscar fin: siguiente GET al mismo nivel o menor
    end = len(s)
    m2 = get_re.search(s, post_m.end())
    if m2:
        end = m2.start()

    canonical = f"""{indent}if path.startswith("/api/notes/") and method == "POST":
{indent}    tail = path.removeprefix("/api/notes/")
{indent}    try:
{indent}        sid, action = tail.split("/", 1)
{indent}        note_id = int(sid)
{indent}    except Exception:
{indent}        note_id = None; action = ""
{indent}    if note_id:
{indent}        if action == "like":
{indent}            code, payload = _json_passthrough_like(note_id)
{indent}        elif action == "view":
{indent}            code, payload = _inc_simple(note_id, "views")
{indent}        elif action == "report":
{indent}            import os
{indent}            threshold = int(os.environ.get("REPORT_THRESHOLD", "5") or "5")
{indent}            fp = _fingerprint(environ)
{indent}            try:
{indent}                code, payload = _report_once(note_id, fp, threshold)
{indent}            except Exception as e:
{indent}                code, payload = 500, {{"ok": False, "error": f"report_failed: {{e}}" }}
{indent}        else:
{indent}            code, payload = 404, {{"ok": False, "error": "unknown_action"}}
{indent}        status, headers, body = _json(code, payload)
{indent}        return _finish(start_response, status, headers, body, method)
"""
    s = s[:start] + canonical + s[end:]
    changed = True
else:
    # No se encontró el bloque; no forzamos nada.
    pass

# ---------- 4) Guardar, gatear y mostrar diff mínimo ----------
if s == raw:
    print("Nada que cambiar; probando compilación igualmente…")

bak = W.with_suffix(".py.repair_notes_actions.bak")
if not bak.exists():
    shutil.copyfile(W, bak)

W.write_text(s, encoding="utf-8")

try:
    py_compile.compile(str(W), doraise=True)
except Exception as e:
    print("✗ py_compile falla tras el fix:", e)
    print("Backup en:", bak)
    # Mostrar ventana útil
    txt = W.read_text(encoding="utf-8").split("\n")
    print("\n--- Ventana 315-360 ---")
    for ln in range(315, 361):
        if 1 <= ln <= len(txt):
            print(f"{ln:4d}: {txt[ln-1]}")
    sys.exit(1)

print(f"✓ Reparación aplicada (helpers removidos: {removed_helpers}) y compilación OK")
print("Backup en:", bak)
