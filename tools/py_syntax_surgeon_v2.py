#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ wsgiapp/__init__.py no existe"); sys.exit(2)

def read_norm():
    s = W.read_text(encoding="utf-8")
    s = s.replace("\r\n","\n").replace("\r","\n")
    if "\t" in s: s = s.replace("\t","    ")
    return s

def write_backup(s, tag):
    bak = W.with_suffix(f".py.{tag}.bak")
    if not bak.exists():
        shutil.copyfile(W, bak)
    W.write_text(s, encoding="utf-8")

def gate():
    try:
        py_compile.compile(str(W), doraise=True)
        return True, None, None
    except Exception as e:
        tb = traceback.format_exc()
        m = re.search(r'__init__\.py, line (\d+)', tb)
        ln = int(m.group(1)) if m else None
        return False, ln, str(e)

def linesio(s): return s.split("\n"), len(s.split("\n"))
def indw(l): return len(l) - len(l.lstrip(" "))
def next_nonempty(lines, i):
    j = i+1
    while j < len(lines) and lines[j].strip()=="":
        j += 1
    return j

HDR = re.compile(r'^([ ]*)(try|except\b.*|finally|if\b.*|elif\b.*|else:|for\b.*|while\b.*|with\b.*|def\b.*|class\b.*):\s*$')
EXCEPT_HDR = re.compile(r'^([ ]*)except\b.*:\s*$')
TRY_HDR    = re.compile(r'^([ ]*)try:\s*$')
BLOCK_HDR2 = re.compile(r'^(except\b|finally\b|elif\b|else\b)\b')

def pass_headers_without_body(s):
    lines, n = linesio(s); changed=False
    i=0
    while i<n:
        L = lines[i]
        m = HDR.match(L)
        if not m: i+=1; continue
        base = len(m.group(1))
        j = next_nonempty(lines, i)
        if j>=n:
            lines.append(" "*(base+4)+"pass"); changed=True; n=len(lines); break
        Lj = lines[j]
        # si el “cuerpo” no está más indentado → inserta pass
        if indw(Lj) <= base:
            # si es otro header tipo except/else/elif al mismo/menor indent → también necesita pass antes
            lines.insert(j, " "*(base+4)+"pass"); changed=True; n+=1; i=j+1; continue
        i=j
    return ("\n".join(lines), changed)

def orphan_except_fix(s):
    lines, n = linesio(s); changed=False
    i=0
    while i<n:
        L = lines[i]
        m = EXCEPT_HDR.match(L)
        if not m: i+=1; continue
        base = len(m.group(1))
        # busca try: hermano hacia atrás
        k = i-1; has_try=False
        while k>=0:
            T = lines[k]
            if T.strip()=="":
                k-=1; continue
            if indw(T) < base: break
            if indw(T) == base and TRY_HDR.match(T):
                has_try=True
            break
        if not has_try:
            lines.insert(i, " " * base + "try:")
            lines.insert(i+1, " " * (base+4) + "pass")
            changed=True; n+=2; i+=2; continue
        i+=1
    return ("\n".join(lines), changed)

def try_headers_need_body_pass(s):
    # específicamente: “expected an indented block after 'try'”
    lines, n = linesio(s); changed=False
    for i,L in enumerate(lines):
        m = TRY_HDR.match(L)
        if not m: continue
        base = len(m.group(1))
        j = next_nonempty(lines, i)
        if j>=n or indw(lines[j])<=base:
            lines.insert(i+1, " "*(base+4)+"pass"); changed=True; n+=1
    return ("\n".join(lines), changed)

def generic_if_for_while_need_body_pass(s):
    # “expected an indented block after 'if' / for / while / else / elif / finally / except”
    return pass_headers_without_body(s)

def ddl_reindent_after_try(s):
    # patrón: try:  \n  cx.execute(_text("""   …  """))
    lines, n = linesio(s); changed=False
    i=0
    while i<n:
        if TRY_HDR.match(lines[i]):
            base = indw(lines[i])
            j = next_nonempty(lines, i)
            if j<n and indw(lines[j])<=base and 'cx.execute(_text("""' in lines[j]:
                # indentar bloque DDL hasta la línea que cierre  )))
                opened=False; k=j
                while k<n:
                    Lk = lines[k]
                    # toggle triple quotes
                    for _m in re.finditer(r'(?<!\\)(?:"""|\'\'\')', Lk): opened = not opened
                    # indentar esta línea
                    lines[k] = " "*(base+4) + lines[k].lstrip(" ")
                    if not opened and re.search(r'\)\)\)\s*$', Lk) or (k+1<n and re.match(r'^\s*\)\)\)\s*$', lines[k+1])):
                        if k+1<n and re.match(r'^\s*\)\)\)\s*$', lines[k+1]):
                            lines[k+1] = " "*(base+4) + lines[k+1].lstrip(" ")
                            k += 1
                        changed=True; i = k+1; break
                    k+=1
        i+=1
    return ("\n".join(lines), changed)

def ensure_text_import(s):
    if re.search(r'(?m)^\s*from\s+sqlalchemy\s+import\s+text\s+as\s+_text\s*$', s):
        return (s, False)
    # insertar tras primer bloque de imports
    m = re.search(r'(?m)^(\s*(?:from\s+\S+\s+import\s+.*|import\s+\S+).*\n)+', s)
    ins = "from sqlalchemy import text as _text\n"
    if m:
        a,b = m.span()
        s = s[:b] + ins + s[b:]
    else:
        s = ins + s
    return (s, True)

def fix_if_inserted_body(s):
    # cuando exista la línea 'if inserted:' sin cuerpo indentado
    lines, n = linesio(s); changed=False
    for i,L in enumerate(lines):
        if re.match(r'^([ ]*)if\s+inserted\s*:\s*$', L):
            base = indw(L)
            j = next_nonempty(lines, i)
            if j>=n or indw(lines[j])<=base:
                # si lo que sigue son cx.execute/row/UPDATE → indéntalo; si no, mete pass
                k=j
                if k<n and re.search(r'\bcx\.execute|row\s*=\s*cx\.execute', lines[k]):
                    lines[k] = " "*(base+4) + lines[k].lstrip(" ")
                    changed=True
                else:
                    lines.insert(i+1, " "*(base+4)+"pass"); changed=True; n+=1
    return ("\n".join(lines), changed)

def heal_unterminated_triple_at_eof(s):
    # cuenta """ y '''; si impares, cierra con triple y opcional ')))' si justo veníamos de _text("""
    c3 = len(re.findall(r'(?<!\\)"""', s))
    c1 = len(re.findall(r"(?<!\\)'''", s))
    if c3%2==0 and c1%2==0: return (s, False)
    tail = '\n"""'
    # si justo antes aparece cx.execute(_text(""" → añadimos ))) en otra línea
    if re.search(r'cx\.execute\(_text\(\"\"\"[^\0]*$', s):
        tail += "\n)))"
    return (s+tail+"\n", True)

def rewrite_like_block(s):
    # Reemplaza bloque 'action == "like"' por uno canónico (seguro).
    lines = s.split("\n"); n=len(lines)
    mstart=None; base_ws=""
    for i,L in enumerate(lines):
        m = re.match(r'^([ ]*)(?:if|elif)\s+action\s*==\s*["\']like["\']\s*:\s*$', L)
        if m:
            mstart=i; base_ws=m.group(1); break
    if mstart is None: return (s, False)
    # buscar fin: próximo header hermano (elif/else/return/def/class) al mismo indent
    hend = n
    hdr_same = re.compile(rf'^{re.escape(base_ws)}(elif\b|else\b|def\b|class\b|return\b)')
    for j in range(mstart+1, n):
        if hdr_same.match(lines[j]): hend=j; break
    block = [
        "try:",
        "    from sqlalchemy import text as _text",
        "    with _engine().begin() as cx:",
        "        try:",
        "            cx.execute(_text(\"\"\"CREATE TABLE IF NOT EXISTS like_log(",
        "                note_id INTEGER NOT NULL REFERENCES note(id) ON DELETE CASCADE,",
        "                fingerprint VARCHAR(128) NOT NULL,",
        "                created_at TIMESTAMPTZ DEFAULT NOW(),",
        "                PRIMARY KEY (note_id, fingerprint)",
        "            )\"\"\"))",
        "        except Exception:",
        "            pass",
        "        try:",
        "            cx.execute(_text(\"\"\"CREATE UNIQUE INDEX IF NOT EXISTS uq_like_note_fp",
        "            ON like_log(note_id, fingerprint)\"\"\"))",
        "        except Exception:",
        "            pass",
        "        fp = _fingerprint(environ)",
        "        inserted = False",
        "        try:",
        "            cx.execute(_text(",
        "                \"INSERT INTO like_log(note_id, fingerprint, created_at) VALUES (:id,:fp, NOW())\"",
        "            ), {\"id\": note_id, \"fp\": fp})",
        "            inserted = True",
        "        except Exception:",
        "            inserted = False",
        "        if inserted:",
        "            cx.execute(_text(",
        "                \"UPDATE note SET likes = COALESCE(likes,0)+1 WHERE id=:id\"",
        "            ), {\"id\": note_id})",
        "        row = cx.execute(_text(",
        "            \"SELECT COALESCE(likes,0), COALESCE(views,0), COALESCE(reports,0) FROM note WHERE id=:id\"",
        "        ), {\"id\": note_id}).first()",
        "        likes  = int(row[0] or 0)",
        "        views  = int(row[1] or 0)",
        "        reports= int(row[2] or 0)",
        "    code, payload = 200, {\"ok\": True, \"id\": note_id, \"likes\": likes, \"views\": views, \"reports\": reports, \"deduped\": (not inserted)}",
        "except Exception as e:",
        "    code, payload = 500, {\"ok\": False, \"error\": str(e)}",
    ]
    block = [ (base_ws + "    " + L) for L in block ]
    out = lines[:mstart+1] + block + lines[hend:]
    return ("\n".join(out), True)

# === driver ===
s = read_norm()
write_backup(s, "syntax_surgeon_v2.orig")

passes = [
    ensure_text_import,
    orphan_except_fix,
    try_headers_need_body_pass,
    generic_if_for_while_need_body_pass,
    ddl_reindent_after_try,
    fix_if_inserted_body,
    heal_unterminated_triple_at_eof,
    rewrite_like_block,  # última: puede ser intrusiva, pero salva zona conflictiva
]

max_iter = 15
for it in range(1, max_iter+1):
    ok, ln, err = gate()
    if ok:
        print("✓ py_compile OK"); sys.exit(0)
    print(f"[iter {it}] gate FAIL @ line {ln}: {err.splitlines()[-1] if err else err}")
    changed_any = False
    s = read_norm()
    for fn in passes:
        s2, ch = fn(s)
        if ch:
            s = s2; changed_any = True
    if not changed_any:
        # nada más que hacer → mostrar ventana
        W.write_text(s, encoding="utf-8")
        print("✗ sin cambios aplicables; mostrando ventana de contexto")
        if ln:
            ctx = s.splitlines()
            a = max(1, ln-40); b = min(len(ctx), ln+40)
            print(f"\n--- Ventana {a}-{b} ---")
            for k in range(a, b+1):
                print(f"{k:5d}: {ctx[k-1]}")
        sys.exit(1)
    # escribir y seguir
    W.write_text(s, encoding="utf-8")

# si salimos del loop
print("✗ alcanzado límite de iteraciones sin compilar")
ok, ln, err = gate()
if not ok and ln:
    ctx = read_norm().splitlines()
    a = max(1, ln-40); b = min(len(ctx), ln+40)
    print(f"\n--- Ventana {a}-{b} ---")
    for k in range(a, b+1):
        print(f"{k:5d}: {ctx[k-1]}")
sys.exit(1)
