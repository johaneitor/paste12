#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"

ROUTES="backend/routes.py"
RUNPY="run.py"
LOG=".tmp/paste12.log"

echo "[+] Backups"
cp "$ROUTES" "$ROUTES.bak.$(date +%s)" || true

###############################################################################
# 1) Saneamos decorators de rutas y quitamos /api/notes -> like_note
###############################################################################
python - "$ROUTES" <<'PY'
import re, sys
p=sys.argv[1]
s=open(p,'r',encoding='utf-8').read()

# Detectar blueprint cuyo name es "api"
m_bp = re.search(r'(?m)^\s*([A-Za-z_]\w*)\s*=\s*Blueprint\(\s*[\'"]api[\'"]\s*,', s)
bp = m_bp.group(1) if m_bp else "bp"

def deco(line): return line if line.endswith("\n") else line+"\n"

def block_range_for_func(name):
    m = re.search(r'(?m)^([ \t]*)def\s+'+re.escape(name)+r'\s*\(', s)
    if not m: return None
    start_def = m.start()
    # subir hasta decoradores contiguos
    i = s.rfind('\n',0,start_def)+1
    deco_start = i
    while True:
        prev = s.rfind('\n',0,deco_start-1)
        if prev < 0: break
        line = s[prev+1:deco_start-1]
        if line.strip().startswith('@'):
            deco_start = prev+1
        else:
            break
    return (deco_start, start_def)

def replace_decorators_strict(name, new_decos):
    global s
    rng = block_range_for_func(name)
    if not rng: return
    a,b = rng
    s = s[:a] + "".join(deco(d) for d in new_decos) + s[b:]

# — Core: /notes GET y POST
replace_decorators_strict("list_notes",  [f"@{bp}.route('/notes', methods=['GET'], endpoint='list_notes')"])
replace_decorators_strict("create_note", [f"@{bp}.route('/notes', methods=['POST'], endpoint='create_note')"])

# — Acciones por ID solamente en /notes/<id>/xxx
replace_decorators_strict("like_note",   [f"@{bp}.route('/notes/<int:note_id>/like', methods=['POST'], endpoint='like_note')"])
replace_decorators_strict("report_note", [f"@{bp}.route('/notes/<int:note_id>/report', methods=['POST'], endpoint='report_note')"])
replace_decorators_strict("view_note",   [f"@{bp}.route('/notes/<int:note_id>/view', methods=['POST'], endpoint='view_note')"])

# — Quitar cualquier route/add_url_rule para '/api/notes' que no sea list_notes/create_note
def remove_strays():
    global s
    # Decorators
    lines = s.splitlines(True)
    out=[]; i=0
    while i<len(lines):
        ln=lines[i]
        if re.match(r'^\s*@[A-Za-z_]\w*\.route\(', ln):
            block=[i]; j=i+1
            while j<len(lines) and lines[j].lstrip().startswith('@'):
                block.append(j); j+=1
            # línea siguiente… debe ser def
            keep=True
            if j<len(lines):
                m=re.match(r'^\s*def\s+([A-Za-z_]\w*)\s*\(', lines[j])
                if m:
                    fname=m.group(1)
                    # solo /notes (relativo al bp) para list/create; todo lo demás con '/notes/<int:...>'
                    for k in block:
                        t = lines[k].replace('"',"'")
                        is_notes = ("'/api/notes'" in t) or ("'/notes'" in t)
                        if is_notes and fname not in ("list_notes","create_note"):
                            # si no es uno de los dos, comentamos
                            lines[k] = "# FIX-REMOVED stray /notes mapping\n"
            i=j+1 if j<len(lines) else j
            continue
        out.append(ln); i+=1
    s=''.join(out)
    # add_url_rule
    s = re.sub(r'(?ms)\b[A-Za-z_]\w*\.add_url_rule\([^)]*(?:[\'"]/api/notes[\'"]|[\'"]/notes[\'"])[^)]*\)[ \t]*\n', 
               '# FIX-REMOVED stray add_url_rule for notes\n', s)

remove_strays()

# — Compactar y grabar
s = re.sub(r'\n{3,}', '\n\n', s)
open(p,'w',encoding='utf-8').write(s)
print("[OK] routes limpiadas y normalizadas")
PY

###############################################################################
# 2) Quitar author_fp del constructor en create_note (lo pone hook/atrib post)
###############################################################################
python - "$ROUTES" <<'PY'
import re, sys
p=sys.argv[1]
s=open(p,'r',encoding='utf-8').read()

# Localizar bloque de la función create_note
m = re.search(r'(?ms)^([ \t]*)def\s+create_note\s*\(.*?\n', s)
if m:
    indent = m.group(1)
    start = m.end()
    # Fin del bloque: prox def al mismo nivel o EOF
    mnext = re.search(r'(?m)^\s*def\s+[A-Za-z_]\w*\(', s[start:])
    end = start + (mnext.start() if mnext else len(s) - start)
    body = s[start:end]

    # Dentro del body, localizar la llamada Note(…)
    def strip_author_kw(call:str)->str:
        # eliminar author_fp=... dentro de la llamada
        call = re.sub(r'\s*author_fp\s*=\s*[^,)\n]+,?', '', call)
        # limpiar comas en exceso antes de ')'
        call = re.sub(r',\s*\)', ')', call)
        return call

    def patch_body(text:str)->str:
        i=0; out=[]
        while True:
            mnote = re.search(r'\bNote\s*\(', text[i:])
            if not mnote:
                out.append(text[i:]); break
            st = i+mnote.start()
            out.append(text[i:st])
            # balancear paréntesis
            j = st; depth=0
            while j<len(text):
                if text[j]=='(':
                    depth+=1
                elif text[j]==')':
                    depth-=1
                    if depth==0: break
                j+=1
            call = text[st:j+1]
            out.append(strip_author_kw(call))
            i=j+1
        return ''.join(out)

    new_body = patch_body(body)

    # Asegurar asignación defensiva antes de db.session.add(n)
    new_body = re.sub(
        r'(n\s*=\s*Note\s*\([^)]*\)\s*\n)',
        r"\1" + indent + "    try:\n" + indent + "        # fallback por si hook no corre\n" + indent + "        getattr(n, 'author_fp')\n" + indent + "    except Exception:\n" + indent + "        try:\n" + indent + "            n.author_fp = client_fingerprint()\n" + indent + "        except Exception:\n" + indent + "            pass\n",
        new_body,
        count=1
    )

    s = s[:start] + new_body + s[end:]
    open(p,'w',encoding='utf-8').write(s)
    print("[OK] author_fp removido del constructor y fallback agregado")
else:
    print("[!] No hallé def create_note() — nada que hacer")
PY

###############################################################################
# 3) Garantizar import de hooks en run.py (para before_insert)
###############################################################################
if ! grep -q "backend\.models_hooks" "$RUNPY"; then
  awk 'NR==1{print "import backend.models_hooks  # hook author_fp before_insert"; print; next} {print}' "$RUNPY" > "$RUNPY.tmp" && mv "$RUNPY.tmp" "$RUNPY"
  echo "[+] Agregado import de backend.models_hooks en run.py"
fi

###############################################################################
# 4) Reiniciar y verificar
###############################################################################
pkill -f "python .*run.py" 2>/dev/null || true
: > "$LOG" || true
nohup python "$RUNPY" >"$LOG" 2>&1 &
sleep 2

echo "[+] URL MAP runtime:"
python - <<'PY'
import importlib
app=getattr(importlib.import_module("run"),"app",None)
rules=[(str(r),sorted([m for m in r.methods if m not in("HEAD","OPTIONS")]),r.endpoint) for r in app.url_map.iter_rules()]
for rule,methods,ep in sorted(rules): print(f"{rule:35s}  {','.join(methods):10s}  {ep}")
bad = [r for r in rules if r[0]=="/api/notes" and r[2].endswith("like_note")]
print("\nSTRAY like_note on /api/notes:", bool(bad))
PY

PORT="$(grep -Eo '127\.0\.0\.1:[0-9]+' "$LOG" 2>/dev/null | tail -n1 | cut -d: -f2 || echo 8000)"
echo "[i] PORT_LOCAL=$PORT"

echo "[+] Smoke GET /api/notes"
curl -i -s "http://127.0.0.1:$PORT/api/notes?page=1" | sed -n '1,80p'
echo
echo "[+] Smoke POST /api/notes"
curl -i -s -X POST -H "Content-Type: application/json" -d '{"text":"surgery-ok","hours":24}' "http://127.0.0.1:$PORT/api/notes" | sed -n '1,120p'
echo
