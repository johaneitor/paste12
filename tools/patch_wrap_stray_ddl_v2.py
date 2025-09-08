#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ wsgiapp/__init__.py no existe"); sys.exit(2)

s = W.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n")
if "\t" in s: s = s.replace("\t","    ")
changed = False

# --- A) asegurar import de sqlalchemy.text como _text (una sola vez, top-level) ---
if not re.search(r'(?m)^\s*from\s+sqlalchemy\s+import\s+text\s+as\s+_text\s*$', s):
    m = re.search(r'(?m)^(\s*(?:from\s+\S+\s+import\s+.*|import\s+\S+).*\n)+', s)
    ins = "from sqlalchemy import text as _text\n"
    if m:
        a,b = m.span()
        s = s[:b] + ins + s[b:]
    else:
        s = ins + s
    changed = True

lines = s.split("\n")
n = len(lines)

def compute_triple_zones(lines):
    """zones[i] = True si la línea i (1-based) está dentro de '''...''' o \"\"\"...\"\"\"."""
    zones = [False] * (len(lines) + 1)  # indexaremos 1..n
    in_triple = False
    quote = None
    for idx, line in enumerate(lines, start=1):
        pos = 0
        while True:
            m = re.search(r'(?<!\\)(?P<q>"""|\'\'\')', line[pos:])
            if not m:
                break
            q = m.group('q')
            pos += m.end()
            if not in_triple:
                in_triple = True
                quote = q
            elif q == quote:
                in_triple = False
                quote = None
        zones[idx] = in_triple
    return zones

zones = compute_triple_zones(lines)

def leading_spaces(line: str) -> int:
    return len(line) - len(line.lstrip(" "))

def is_python_stmt(l: str) -> bool:
    return re.match(r'^\s*(def|class|try:|except|finally:|with\s|if\s|elif\s|else:|for\s|while\s|return\b|from\s|import\s|@|app\s*=|start_response\(|cx\.execute\()', l) is not None

ddl_start = re.compile(r'^\s*CREATE\s+(?:TABLE|UNIQUE\s+INDEX|INDEX)\b', re.I)

out = []
i = 1
while i <= n:
    line = lines[i-1]
    # Sólo considerar si NO estamos dentro de triple-comilla y la línea empieza con CREATE ...
    if not zones[i] and ddl_start.match(line):
        base_indent = leading_spaces(line)
        start = i
        j = i
        while j <= n:
            l2 = lines[j-1]
            if j != start and not zones[j]:
                if is_python_stmt(l2):
                    break
                if leading_spaces(l2) < base_indent and l2.strip() != "":
                    break
            # Heurística de fin: línea que cierra con ')' (opcional ';'), y lo siguiente ya es Python o fin
            if re.search(r'\)\s*;?\s*$', l2):
                if j == n or (j < n and is_python_stmt(lines[j])):
                    j += 1
                    break
            j += 1

        # Extraer bloque SQL (desde start hasta j-1 inclusive)
        end_idx = min(j-1, n)
        sql_block = "\n".join(lines[start-1:end_idx])
        # Normalizar indent interno removiendo base_indent
        sql_lines = sql_block.split("\n")
        norm = []
        for sl in sql_lines:
            if sl.strip() == "":
                norm.append("")
            elif sl.startswith(" " * base_indent):
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

        out.append(wrapped)
        changed = True
        i = end_idx + 1
        continue
    else:
        out.append(line)
        i += 1

s2 = "\n".join(out)
if s2 != s:
    s = s2
    changed = True

# --- C) Guardar + backup + gate ---
if changed:
    bak = W.with_suffix(".py.wrap_stray_ddl_v2.bak")
    if not bak.exists():
        shutil.copyfile(W, bak)
    W.write_text(s, encoding="utf-8")
    print(f"patched: wrapped stray DDL blocks (v2) | backup={bak.name}")
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
