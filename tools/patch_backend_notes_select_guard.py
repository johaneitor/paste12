#!/usr/bin/env python3
import re, pathlib, shutil, sys, py_compile

W = pathlib.Path("wsgiapp/__init__.py")
src = W.read_text(encoding="utf-8", errors="ignore")

bak = W.with_suffix(".notes_select.bak")
if not bak.exists():
    shutil.copyfile(W, bak)

orig = src
# 1) Bajar 'author_fp' del SELECT de listado
#   Match común (con espacios flexibles) para la consulta "SELECT ... FROM note ORDER BY ..."
pat = re.compile(
    r'(SELECT\s+)(id,\s*text,\s*title,\s*url,\s*summary,\s*content,\s*timestamp,\s*expires_at,\s*likes,\s*views,\s*reports,\s*author_fp)(\s+FROM\s+note\s+ORDER\s+BY)',
    re.IGNORECASE
)
src = pat.sub(r'\1id, text, title, url, summary, content, timestamp, expires_at, likes, views, reports\3', src)

# 2) Por si hay otra variante similar (sólo por seguridad)
pat2 = re.compile(
    r'(SELECT\s+)(.*?author_fp\s*,?\s*)(\s+FROM\s+note\s+ORDER\s+BY)',
    re.IGNORECASE | re.DOTALL
)
src = pat2.sub(lambda m: m.group(1) + re.sub(r'\s*,?\s*author_fp\s*', '', m.group(2), flags=re.IGNORECASE) + m.group(3), src)

# 3) Normalizar fila: si no existe 'author_fp', setear None.
if "_normalize_row" in src and "author_fp" in src:
    # ya suele mapear por claves; si no, añadimos fill-in post mapeo
    if "def _normalize_row(" not in src or "row.get('author_fp')" in src:
        pass
    else:
        src = src.replace(
            "return row",
            "row.setdefault('author_fp', None)\n    return row"
        )

if src == orig:
    print("OK: no se detectaron cambios (quizás ya estaba sin author_fp).")
else:
    W.write_text(src, encoding="utf-8")
    print(f"patched: SELECT sin author_fp | backup={bak.name}")

# Gate compilación
try:
    py_compile.compile(str(W), doraise=True)
    print("✓ py_compile OK")
except Exception as e:
    print("✗ py_compile FAIL:", e)
    sys.exit(1)
