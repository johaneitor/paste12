#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"

ROUTES="backend/routes.py"
RUNPY="run.py"
LOG=".tmp/paste12.log"
DB="${PASTE12_DB:-app.db}"

[ -f "$ROUTES" ] || { echo "[!] No encuentro $ROUTES"; exit 1; }

echo "[+] Backups"
cp "$ROUTES" "$ROUTES.bak.$(date +%s)" || true

###############################################################################
# 1) Saneamos RUTAS: /api/notes GET->list_notes, POST->create_note
#    like/report/view SOLO: /notes/<int:note_id>/(like|report|view) POST
###############################################################################
python - "$ROUTES" <<'PY'
import re, sys
p=sys.argv[1]
s=open(p,'r',encoding='utf-8').read()

# Detectar nombre del blueprint cuyo name es "api"
m_bp = re.search(r'(?m)^\s*([A-Za-z_]\w*)\s*=\s*Blueprint\(\s*[\'"]api[\'"]\s*,', s)
bp = m_bp.group(1) if m_bp else "bp"

def deco(line): return line if line.endswith("\n") else line+"\n"

def block_range_for_func(name:str):
    m = re.search(r'(?m)^([ \t]*)def\s+'+re.escape(name)+r'\s*\(', s)
    if not m: return None
    start_def = m.start()
    # subir hasta el inicio del bloque de decoradores contiguos
    i = s.rfind('\n',0,start_def) + 1
    deco_start = i
    while True:
        prev = s.rfind('\n',0,deco_start-1)
        if prev < 0: break
        line = s[prev+1:deco_start-1]
        if line.strip().startswith('@'):
            deco_start = prev+1
            continue
        break
    return (deco_start, start_def)

def replace_decorators_strict(name:str, new_decos:list[str]):
    global s
    rng = block_range_for_func(name)
    if not rng: return
    a,b = rng
    # Eliminar CUALQUIER decorador anterior y dejar SOLO los que indicamos
    s = s[:a] + "".join(deco(d) for d in new_decos) + s[b:]

def purge_stray_notes_routes():
    """Comenta cualquier @*.route('/api/notes'|'/notes') que NO esté en los bloques de
       list_notes o create_note; así evitamos que se cuele like_note con GET."""
    global s
    rng_list = block_range_for_func("list_notes")
    rng_crea = block_range_for_func("create_note")
    keep_ranges = []
    if rng_list: keep_ranges.append(rng_list)
    if rng_crea: keep_ranges.append(rng_crea)

    lines = s.splitlines(True)
    out=[]; i=0
    while i<len(lines):
        ln=lines[i]
        if re.match(r'^\s*@[A-Za-z_]\w*\.route\(', ln):
            # bloque de decoradores contiguos
            block_idx=[]; j=i
            while j<len(lines) and lines[j].lstrip().startswith('@'):
                block_idx.append(j); j+=1
            # ¿cae este bloque dentro de los rangos permitidos?
            # reconstruimos offsets
            off=0; pos=[]
            for k,li in enumerate(lines): 
                pos.append(off); off+=len(li)
            bstart = pos[i]; bend = pos[j-1]+len(lines[j-1])

            def inside_any(a,b):
                for (A,B) in keep_ranges:
                    if a>=A and b<=B: return True
                return False

            for k in block_idx:
                t = lines[k].replace('"',"'")
                is_notes = ("'/api/notes'" in t) or ("'/notes'" in t)
                if is_notes and not inside_any(bstart,bend):
                    out.append("# FIX-REMOVED stray /notes mapping\n")
                else:
                    out.append(lines[k])
            if j<len(lines):
                out.append(lines[j]); i=j+1; continue
            i=j; continue
        out.append(ln); i+=1
    s=''.join(out)

def remove_add_url_rule_strays():
    """Comenta cualquier add_url_rule para '/api/notes' o '/notes' que no apunte
       a list_notes/create_note."""
    global s
    def find_close(text, start):
        depth=0
        for i in range(start,len(text)):
            c=text[i]
            if c=='(':
                depth+=1
            elif c==')':
                depth-=1
                if depth==0: return i
        return None
    i=0
    while True:
        m=re.search(r'(?ms)\b[A-Za-z_]\w*\.add_url_rule\s*\(', s[i:])
        if not m: break
        start=i+m.start()
        openp = s.find('(', start)
        endp = find_close(s, openp) or (openp+1)
        call = s[start:endp+1]
        q = call.replace('"',"'")
        if ("'/api/notes'" in q) or ("'/notes'" in q):
            ok = re.search(r"view_func\s*=\s*(create_note|list_notes)\b", call) is not None
            if not ok:
                s = s[:start] + "# FIX-REMOVED wrong add_url_rule for notes\n" + s[endp+1:]
                i = start+1; continue
        i = endp+1

# 1) Purgar mapeos erróneos
purge_stray_notes_routes()
remove_add_url_rule_strays()

# 2) Normalizar decoradores STRICT de las funciones core
replace_decorators_strict("list_notes",  [f"@{bp}.route('/notes', methods=['GET'], endpoint='list_notes')"])
replace_decorators_strict("create_note", [f"@{bp}.route('/notes', methods=['POST'], endpoint='create_note')"])

# 3) like/report/view SOLO con /notes/<int:note_id>/* POST
for fname, tail in [("like_note","like"), ("report_note","report"), ("view_note","view")]:
    replace_decorators_strict(fname, [f"@{bp}.route('/notes/<int:note_id>/{tail}', methods=['POST'], endpoint='{fname}')"])

# 4) Convertir cualquier residuo de '/api/notes' en '/notes' (relativo al bp) en decoradores
s = re.sub(r"(@\s*"+re.escape(bp)+r"\.route\(\s*['\"])\/api\/notes", r"\1/notes", s)

# 5) Compactar
s = re.sub(r'\n{3,}', '\n\n', s)

open(p,'w',encoding='utf-8').write(s)
print("[OK] routes saneadas.")
PY

###############################################################################
# 2) MODELO Note: asegurar columna author_fp en clase
###############################################################################
python - <<'PY'
import re, sys, os, glob
candidates = []
for path in glob.glob("backend/**/*.py", recursive=True):
    try:
        with open(path,'r',encoding='utf-8') as f:
            if re.search(r'(?m)^class\s+Note\s*\(', f.read()):
                candidates.append(path)
    except Exception:
        pass

if not candidates:
    print("[!] No encontré class Note en backend/*.py")
    sys.exit(0)

# Elegimos el más probable (backend/models.py preferente)
candidates.sort(key=lambda p: (0 if p.endswith("backend/models.py") else 1, p))
path = candidates[0]
src = open(path,'r',encoding='utf-8').read()

if "author_fp" in src:
    print(f"[*] {path} ya declara author_fp")
else:
    m = re.search(r'(?m)^class\s+Note\s*\([^)]*\):\s*\n', src)
    if not m:
        print(f"[!] No pude insertar author_fp en {path} (no hallé el cuerpo).")
    else:
        start = m.end()
        # descubrir indent de atributos
        m2 = re.search(r'(?m)^([ \t]+)\S', src[start:])
        indent = m2.group(1) if m2 else '    '
        # antes del primer def dentro de la clase
        m3 = re.search(r'(?m)^%sdef\s' % re.escape(indent), src[start:])
        at = start + (m3.start() if m3 else 0)
        line = f"{indent}author_fp = db.Column(db.String(64), nullable=False, index=True)\n"
        src = src[:at] + line + src[at:]
        open(path,'w',encoding='utf-8').write(src)
        print(f"[OK] Inserté author_fp en {path}")
PY

###############################################################################
# 3) Migración SQLite (si existe DB local)
###############################################################################
if command -v sqlite3 >/dev/null 2>&1 && [ -f "$DB" ]; then
  echo "[+] Verificando esquema SQLite en $DB"
  if ! sqlite3 "$DB" 'PRAGMA table_info(note);' | awk -F'|' '{print $2}' | grep -q '^author_fp$'; then
    echo "    -> ALTER TABLE note ADD COLUMN author_fp TEXT NOT NULL DEFAULT 'noctx'"
    sqlite3 "$DB" 'ALTER TABLE note ADD COLUMN author_fp TEXT NOT NULL DEFAULT "noctx";'
    sqlite3 "$DB" 'CREATE INDEX IF NOT EXISTS idx_note_author_fp ON note(author_fp);'
  else
    echo "    author_fp ya existe en DB"
  fi
else
  echo "[i] Omito migración SQLite (no sqlite3 o no DB local)"
fi

###############################################################################
# 4) Reinicio y verificación (URL MAP y smokes)
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
has_get=any(r for r in rules if r[0]=="/api/notes" and "GET" in r[1] and r[2].endswith("list_notes"))
has_post=any(r for r in rules if r[0]=="/api/notes" and "POST" in r[1] and r[2].endswith("create_note"))
bad_like = any(r for r in rules if r[0]=="/api/notes" and r[2].endswith("like_note"))
print(f"\nCHECK  /api/notes GET→list_notes:{has_get}  POST→create_note:{has_post}  stray_like_on_/api/notes:{bad_like}")
PY

PORT="$(grep -Eo '127\.0\.0\.1:[0-9]+' "$LOG" 2>/dev/null | tail -n1 | cut -d: -f2 || echo 8000)"
echo "[i] PORT_LOCAL=$PORT"

echo "[+] Smoke GET /api/notes"
curl -i -s "http://127.0.0.1:$PORT/api/notes?page=1" | sed -n '1,80p'
echo
echo "[+] Smoke POST /api/notes"
curl -i -s -X POST -H "Content-Type: application/json" -d '{"text":"end-to-end-ok","hours":24}' "http://127.0.0.1:$PORT/api/notes" | sed -n '1,120p'
echo
