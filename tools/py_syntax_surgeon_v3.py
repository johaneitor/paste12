#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback
W = pathlib.Path("wsgiapp/__init__.py")

def rd():
    s = W.read_text(encoding="utf-8")
    s = s.replace("\r\n","\n").replace("\r","\n")
    if "\t" in s: s = s.replace("\t","    ")
    # limpia posibles chars de control que rompen parseo
    s = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f]', '', s)
    return s

def wr(s, tag=None):
    if tag:
        bak = W.with_suffix(f".py.{tag}.bak")
        if not bak.exists(): shutil.copyfile(W, bak)
    W.write_text(s, encoding="utf-8")

def gate():
    try:
        py_compile.compile(str(W), doraise=True); return (True, None, "")
    except Exception as e:
        tb = traceback.format_exc()
        m = (re.search(r'__init__\.py, line (\d+)', tb) or
             re.search(r'File ".*__init__\.py", line (\d+)', tb) or
             re.search(r'line (\d+)', tb))
        return (False, int(m.group(1)) if m else None, tb)

def indw(l): return len(l) - len(l.lstrip(" "))
def next_ne(lines, i):
    j=i+1
    while j < len(lines) and lines[j].strip()=="":
        j+=1
    return j

HDR_ANY = re.compile(r'^([ ]*)(try|except\b.*|finally|if\b.*|elif\b.*|else:|for\b.*|while\b.*|with\b.*|def\b.*|class\b.*):\s*$')
HDR_MISS_COLON = re.compile(r'^([ ]*)(try|except\b.*|finally|if\b.*|elif\b.*|else|for\b.*|while\b.*|with\b.*|def\b.*|class\b.*)\s*(#.*)?$')
TRY_HDR = re.compile(r'^([ ]*)try:\s*$')
EXCEPT_HDR = re.compile(r'^([ ]*)except\b.*:\s*$')
BLOCK_HDR_ONLY = re.compile(r'^(except\b|finally\b|elif\b|else\b)\b')

def ensure_text_import(s):
    if re.search(r'(?m)^\s*from\s+sqlalchemy\s+import\s+text\s+as\s+_text\s*$', s):
        return (s, False)
    m = re.search(r'(?m)^(\s*(?:from\s+\S+\s+import\s+.*|import\s+\S+).*\n)+', s)
    ins = "from sqlalchemy import text as _text\n"
    if m: a,b=m.span(); s=s[:b]+ins+s[b:]
    else: s=ins+s
    return (s, True)

def fix_missing_colons(s):
    # añade ":" cuando falta en headers
    out=[]; ch=False
    for L in s.split("\n"):
        if HDR_ANY.match(L): out.append(L); continue
        m = HDR_MISS_COLON.match(L)
        if m and m.group(2):
            base=m.group(1) or ""
            # evita casos como 'else' seguido de no-header a la derecha
            if L.strip() in ("else","finally") or re.match(r'^\s*(try|if|elif|for|while|with|def|class)\b', L.strip()):
                out.append(L.rstrip()+" :")  # espacio antes de colon por si hay comentario
                ch=True
            else:
                out.append(L)
        else:
            out.append(L)
    return ("\n".join(out), ch)

def orphan_except_fix(s):
    lines=s.split("\n"); n=len(lines); ch=False; i=0
    while i<n:
        L=lines[i]
        m = EXCEPT_HDR.match(L)
        if not m: i+=1; continue
        base=len(m.group(1))
        # busca try hermano
        k=i-1; has=False
        while k>=0 and lines[k].strip()=="":
            k-=1
        if k>=0 and indw(lines[k])==base and TRY_HDR.match(lines[k]): has=True
        if not has:
            lines.insert(i, " " * base + "try:")
            lines.insert(i+1, " " * (base+4) + "pass")
            n+=2; ch=True; i+=2; continue
        i+=1
    return ("\n".join(lines), ch)

def pass_for_empty_bodies(s):
    lines=s.split("\n"); n=len(lines); ch=False; i=0
    while i<n:
        L=lines[i]
        m = HDR_ANY.match(L)
        if not m: i+=1; continue
        base=len(m.group(1))
        j=next_ne(lines,i)
        if j>=n:
            lines.append(" "*(base+4)+"pass"); n=len(lines); ch=True; break
        if indw(lines[j])<=base:
            lines.insert(j, " "*(base+4)+"pass"); n+=1; ch=True; i=j+1; continue
        i=j
    return ("\n".join(lines), ch)

def ddl_reindent_after_try(s):
    lines=s.split("\n"); n=len(lines); ch=False; i=0
    while i<n:
        L=lines[i]
        m=TRY_HDR.match(L)
        if not m: i+=1; continue
        base=len(m.group(1))
        j=next_ne(lines,i)
        if j<n and indw(lines[j])<=base and 'cx.execute(_text("""' in lines[j]:
            # reindent hasta cerrar triple y ')))'
            opened=False; k=j
            while k<n:
                Lk=lines[k]
                for _m in re.finditer(r'(?<!\\)(?:"""|\'\'\')', Lk):
                    opened=not opened
                lines[k] = " "*(base+4) + lines[k].lstrip(" ")
                if (not opened and re.search(r'\)\)\)\s*$', Lk)) or (k+1<n and re.match(r'^\s*\)\)\)\s*$', lines[k+1])):
                    if k+1<n and re.match(r'^\s*\)\)\)\s*$', lines[k+1]):
                        lines[k+1]=" "*(base+4)+lines[k+1].lstrip(" ")
                        k+=1
                    ch=True; i=k+1; break
                k+=1
        else:
            i+=1
    return ("\n".join(lines), ch)

def fix_if_inserted(s):
    lines=s.split("\n"); n=len(lines); ch=False
    for i,L in enumerate(lines):
        m=re.match(r'^([ ]*)if\s+inserted\s*:\s*$', L)
        if not m: continue
        base=len(m.group(1))
        j=next_ne(lines,i)
        if j>=n or indw(lines[j])<=base:
            # indenta instrucción siguiente si es cx.execute/row, si no: pass
            if j<n and re.search(r'\bcx\.execute|row\s*=\s*cx\.execute', lines[j]):
                lines[j]=" "*(base+4)+lines[j].lstrip(" "); ch=True
            else:
                lines.insert(i+1, " "*(base+4)+"pass"); ch=True
    return ("\n".join(lines), ch)

def heal_triple_quotes(s):
    c3=len(re.findall(r'(?<!\\)"""', s))
    c1=len(re.findall(r"(?<!\\)'''", s))
    if c3%2==0 and c1%2==0: return (s, False)
    tail = '\n"""'
    if re.search(r'cx\.execute\(_text\(\"\"\"[^\0]*$', s):
        tail += "\n)))"
    return (s+tail+"\n", True)

def rewrite_like_block(s):
    lines=s.split("\n"); n=len(lines); mstart=None; base_ws=""
    for i,L in enumerate(lines):
        m=re.match(r'^([ ]*)(?:if|elif)\s+action\s*==\s*["\']like["\']\s*:\s*$', L)
        if m: mstart=i; base_ws=m.group(1); break
    if mstart is None: return (s, False)
    # next sibling
    hend=n
    hdr_same=re.compile(rf'^{re.escape(base_ws)}(elif\b|else\b|def\b|class\b|return\b)')
    for j in range(mstart+1,n):
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

passes = [
    ensure_text_import,
    fix_missing_colons,
    orphan_except_fix,
    pass_for_empty_bodies,
    ddl_reindent_after_try,
    fix_if_inserted,
    heal_triple_quotes,
    rewrite_like_block,
]

def run():
    s = rd()
    wr(s, "syntax_surgeon_v3.orig")
    for it in range(1, 20):
        ok, ln, tb = gate()
        if ok:
            print("✓ py_compile OK"); return 0
        print(f"[iter {it}] gate FAIL @ line {ln or '<?>'}")
        s = rd()
        changed=False
        for fn in passes:
            s2, ch = fn(s); 
            if ch: changed=True; s=s2
        if not changed:
            # sin cambios, muestra ventana (si hay línea)
            W.write_text(s, encoding="utf-8")
            print("✗ sin cambios aplicables; usa tools/py_gate_verbose.py para ventana completa")
            if ln:
                txt=s.splitlines(); a=max(1, ln-40); b=min(len(txt), ln+40)
                print(f"\n--- Ventana {a}-{b} ---")
                for i in range(a, b+1):
                    print(f"{i:5d}: {txt[i-1]}")
            return 1
        W.write_text(s, encoding="utf-8")
    print("✗ límite de iteraciones")
    return 1

if __name__=="__main__":
    sys.exit(run())
