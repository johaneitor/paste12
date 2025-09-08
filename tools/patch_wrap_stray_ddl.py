#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ wsgiapp/__init__.py no existe"); sys.exit(2)

s = W.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n")
if "\t" in s: s = s.replace("\t","    ")
changed = False

# --- A) asegurar import de sqlalchemy.text como _text (una vez) ---
if not re.search(r'(?m)^\s*from\s+sqlalchemy\s+import\s+text\s+as\s+_text\s*$', s):
    # insertar tras el primer bloque de imports top-level
    m = re.search(r'(?m)^(\s*(?:from\s+\S+\s+import\s+.*|import\s+\S+).*\n)+', s)
    ins = "from sqlalchemy import text as _text\n"
    if m:
        a,b = m.span()
        s = s[:b] + ins + s[b:]
    else:
        s = ins + s
    changed = True

# --- B) localizar si estamos dentro de triple-comilla (heurística) ---
def mark_triple_zones(text: str):
    zones = [False]* (len(text.splitlines())+1)
    in_triple = False
    quote = None
    i = 0
    for idx, line in enumerate(text.splitlines(), start=1):
        # contar apariciones de """ o ''' (sin escapar) para toggle
        for m in re.finditer(r'(?<!\\)(?P<q>"""|\'\'\')', line):
            if not in_triple:
                in_triple = True
                quote = m.group('q')
            else:
                # cerrar sólo si coincide
                if m.group('q') == quote:
                    in_triple = False
                    quote = None
        zones[idx] = in_triple
    return zones

zones = mark_triple_zones(s)
lines = s.split("\n")
n = len(lines)

def leading_spaces(line: str) -> int:
    return len(line) - len(line.lstrip(" "))

def is_python_stmt(l: str) -> bool:
    return re.match(r'^\s*(def|class|try:|except|finally:|with\s|if\s|elif\s|else:|for\s|while\s|return\b|from\s|import\s|@|app\s*=|cx\.execute|start_response\()', l) is not None

ddl_start = re.compile(r'^\s*CREATE\s+(?:TABLE|UNIQUE\s+INDEX|INDEX)\b', re.I)

i = 1
out = []
while i <= n:
    line = lines[i-1]
    if not zones[i] and ddl_start.match(line):
        base_indent = leading_spaces(line)
        start = i
        j = i
        # acumular hasta que huela a fin del bloque DDL
        while j <= n:
            l2 = lines[j-1]
            if j != start and not zones[j]:
                if is_python_stmt(l2):   # siguiente sentencia Python → fin
                    break
                # si encontramos línea sin indent menor al del bloque, asumimos fin
                if leading_spaces(l2) < base_indent and l2.strip() != "":
                    break
            # heurística de cierre por ');' o línea vacía seguida de python
            if re.search(r'\)\s*;?\s*$', l2):
                # mirar siguiente si es python o fin
                if j == n or (j < n and is_python_stmt(lines[j])):
                    j += 1
                    break
            j += 1
        # extraer bloque SQL
        sql_block = "\n".join(lines[start-1:j-1 if j<=n else n])
        # normalizar indent interno del SQL (quitar base_indent)
        sql_lines = sql_block.split("\n")
        norm = []
        for sl in sql_lines:
            if sl.strip() == "":
                norm.append("")
            else:
                # quitar como mínimo base_indent espacios si están
                if sl.startswith(" " * base_indent):
                    norm.append(sl[base_indent:])
                else:
                    norm.append(sl.lstrip(" "))
        sql_norm = "\n".join(norm).rstrip()

        indent = " " * base_indent
        wrapped = (
f"{indent}try:\n"
f"{indent}    with _engine().begin() as cx:\n"
f"{indent}        cx.execute(_text(\"\"\"\n{sql_norm}\n\"\"\"))\n"
f"{indent}except Exception:\n"
f"{indent}    pass"
        )

        # reemplazar bloque original
        out.append(wrapped)
        changed = True
        i = j
        continue
    else:
        out.append(line)
        i += 1

s2 = "\n".join(out)
if s2 != s:
    s = s2
    changed = True

# --- C) guardar + backup + gate ---
if changed:
    bak = W.with_suffix(".py.wrap_stray_ddl.bak")
    if not bak.exists():
        shutil.copyfile(W, bak)
    W.write_text(s, encoding="utf-8")
    print(f"patched: wrapped stray DDL blocks | backup={bak.name}")
else:
    print("OK: no stray DDL blocks")

try:
    py_compile.compile(str(W), doraise=True)
    print("✓ py_compile OK")
except Exception as e:
    print("✗ py_compile falla:", e)
    tb = traceback.format_exc()
    m = re.search(r'__init__\.py, line (\d+)', tb)
    if m:
        ln = int(m.group(1))
        start = max(1, ln-25); end = ln+25
        txt = W.read_text(encoding="utf-8").splitlines()
        print(f"\n--- Ventana {start}-{end} ---")
        for k in range(start, min(end, len(txt))+1):
            print(f"{k:5d}: {txt[k-1]}")
    sys.exit(1)
