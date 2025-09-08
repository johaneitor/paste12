#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)

def rd():
    s = W.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n")
    if "\t" in s: s = s.replace("\t","    ")
    return s

def gate():
    try:
        py_compile.compile(str(W), doraise=True)
        print("✓ py_compile OK"); return True
    except Exception as e:
        tb = traceback.format_exc()
        print("✗ py_compile FAIL\n" + tb); return False

s = rd()
lines = s.split("\n")
n = len(lines)

# 1) localizar encabezado: if/elif action == "like":
pat_like = re.compile(r'^([ ]*)(?:if|elif)\s+action\s*==\s*["\']like["\']\s*:\s*$')
start = None
base_ws = ""

for i, L in enumerate(lines):
    m = pat_like.match(L)
    if m:
        start = i
        base_ws = m.group(1)
        break

if start is None:
    print("✗ no hallé encabezado if/elif action == \"like\"")
    sys.exit(1)

# 2) límite del bloque “like”: siguiente encabezado al MISMO nivel (elif/else) o hasta un pivote común
pat_sibling = re.compile(rf'^{re.escape(base_ws)}(elif\s+action\s*==\s*["\'](view|report)["\']\s*:\s*|else:\s*)$')
end = None
for j in range(start+1, n):
    L = lines[j]
    if pat_sibling.match(L):
        end = j
        break
# fallback: cortar antes del _json(...) si no aparece un sibling (situación corrupta)
if end is None:
    for j in range(start+1, n):
        if lines[j].lstrip().startswith("status, headers, body = _json"):
            end = j
            break
if end is None:
    end = n

# 3) construir bloque canónico del caso "like" (indent = base + 4)
B = base_ws + "    "
block = [
    f"{B}try:",
    f"{B}    from sqlalchemy import text as _text",
    f"{B}    with _engine().begin() as cx:",
    f"{B}        # DDL idempotente",
    f"{B}        try:",
    f"{B}            cx.execute(_text(\"\"\"CREATE TABLE IF NOT EXISTS like_log(",
    f"{B}                note_id INTEGER NOT NULL REFERENCES note(id) ON DELETE CASCADE,",
    f"{B}                fingerprint VARCHAR(128) NOT NULL,",
    f"{B}                created_at TIMESTAMPTZ DEFAULT NOW(),",
    f"{B}                PRIMARY KEY (note_id, fingerprint)",
    f"{B}            )\"\"\"))",
    f"{B}        except Exception:",
    f"{B}            pass",
    f"{B}        try:",
    f"{B}            cx.execute(_text(\"\"\"CREATE UNIQUE INDEX IF NOT EXISTS uq_like_note_fp",
    f"{B}            ON like_log(note_id, fingerprint)\"\"\"))",
    f"{B}        except Exception:",
    f"{B}            pass",
    f"{B}        # Insert + update",
    f"{B}        fp = _fingerprint(environ)",
    f"{B}        inserted = False",
    f"{B}        try:",
    f"{B}            cx.execute(_text(",
    f"{B}                \"INSERT INTO like_log(note_id, fingerprint, created_at) VALUES (:id,:fp, NOW())\"",
    f"{B}            ), {{\"id\": note_id, \"fp\": fp}})",
    f"{B}            inserted = True",
    f"{B}        except Exception:",
    f"{B}            inserted = False",
    f"{B}        if inserted:",
    f"{B}            cx.execute(_text(",
    f"{B}                \"UPDATE note SET likes = COALESCE(likes,0)+1 WHERE id=:id\"",
    f"{B}            ), {{\"id\": note_id}})",
    f"{B}        row = cx.execute(_text(",
    f"{B}            \"SELECT COALESCE(likes,0), COALESCE(views,0), COALESCE(reports,0) FROM note WHERE id=:id\"",
    f"{B}        ), {{\"id\": note_id}}).first()",
    f"{B}        likes  = int(row[0] or 0)",
    f"{B}        views  = int(row[1] or 0)",
    f"{B}        reports= int(row[2] or 0)",
    f"{B}    code, payload = 200, {{\"ok\": True, \"id\": note_id, \"likes\": likes, \"views\": views, \"reports\": reports, \"deduped\": (not inserted)}}",
    f"{B}except Exception as e:",
    f"{B}    code, payload = 500, {{\"ok\": False, \"error\": f\"like_failed: {{e}}\"}}",
]

# reemplazar cuerpo del caso like
new_lines = lines[:start+1] + block + lines[end:]
lines = new_lines
n = len(lines)

# 4) Reanclar encabezados siguientes (elif view/report y else) al MISMO nivel que el 'if like'
pat_any_sibling = re.compile(r'^\s*(elif\s+action\s*==\s*["\'](view|report)["\']\s*:\s*|else:\s*)$')
k = start+1+len(block)
while k < n:
    L = lines[k]
    if L.strip()=="":
        k += 1; continue
    if pat_any_sibling.match(L):
        # normaliza indent al base_ws
        lines[k] = base_ws + L.lstrip()
        k += 1
        continue
    # si llegamos a la “salida” común (_json/return) paramos
    if lines[k].lstrip().startswith("status, headers, body = _json") or \
       lines[k].lstrip().startswith("return _finish"):
        break
    k += 1

out = "\n".join(lines)
bak = W.with_suffix(".py.normalize_like_block.bak")
if not bak.exists():
    shutil.copyfile(W, bak)
W.write_text(out, encoding="utf-8")
print(f"patched: like-block reescrito y siblings reanclados | backup={bak.name}")

# Gate rápido
sys.exit(0 if gate() else 1)
