#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ wsgiapp/__init__.py no existe"); sys.exit(2)

raw = W.read_text(encoding="utf-8")
s = raw
changed = False

# 1) Renombrar alias del módulo json que use _json
pat_import1 = re.compile(r'^\s*import\s+json\s+as\s+_json\s*$', re.M)
pat_import2 = re.compile(r'^\s*from\s+json\s+import\s+([A-Za-z0-9_,\s]+)\s+as\s+_json\s*$', re.M)

if pat_import1.search(s):
    s = pat_import1.sub('import json as _json_mod', s)
    changed = True

if pat_import2.search(s):
    s = pat_import2.sub(r'from json import \1 as _json_mod', s)
    changed = True

# 2) Reparar usos del módulo que quedaron como _json.dumps / _json.loads
s2 = re.sub(r'\b_json\.(dumps|loads)\(', r'_json_mod.\1(', s)
if s2 != s:
    s = s2
    changed = True

# 3) Asegurar helper de respuesta JSON (función) y que use _json_mod.dumps
helper_fn = r'''
def _json(code, payload):
    """Devuelve (status, headers, body) para JSON con no-store; usa _json_mod.dumps."""
    try:
        import json as _json_mod  # fallback si no existe el alias arriba
    except Exception:
        import json as _json_mod
    body = _json_mod.dumps(payload, default=str).encode("utf-8")
    status = f"{code} OK"
    headers = [
        ("Content-Type", "application/json; charset=utf-8"),
        ("Content-Length", str(len(body))),
        ("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0"),
        ("X-WSGI-Bridge", "1"),
    ]
    return status, headers, body
'''.lstrip('\n')

# Si NO existe def _json( → la insertamos al inicio del archivo (tras imports) o al final.
if not re.search(r'^\s*def\s+_json\s*\(', s, flags=re.M):
    # Intentar insertar después del bloque de imports
    m = re.search(r'^(?:from\s+\S+\s+import\s+.*\n|import\s+\S+.*\n)+', s, flags=re.M)
    if m:
        s = s[:m.end()] + "\n" + helper_fn + "\n" + s[m.end():]
    else:
        s = helper_fn + "\n" + s
    changed = True
else:
    # Existe un def _json. Aseguramos que usa _json_mod.dumps() (no se rompe si ya está bien).
    s2 = re.sub(
        r'(^\s*def\s+_json\s*\([^\)]*\):[\s\S]*?)\bjson\.dumps\(',
        r'\1_json_mod.dumps(',
        s, flags=re.M
    )
    s2 = re.sub(
        r'(^\s*def\s+_json\s*\([^\)]*\):[\s\S]*?)\b_json\.dumps\(',
        r'\1_json_mod.dumps(',
        s2, flags=re.M
    )
    if s2 != s:
        s = s2
        changed = True

# 4) Guardar backup y escribir si cambió
if s == raw:
    print("OK: no se detectó shadowing; nada que cambiar.")
else:
    bak = W.with_suffix(".py.fix_json_shadow.bak")
    if not bak.exists():
        shutil.copyfile(W, bak)
    W.write_text(s, encoding="utf-8")
    print("patched: json alias → _json_mod y helper _json verificado")

# 5) Gate de compilación
py_compile.compile(str(W), doraise=True)
print("✓ py_compile OK")
