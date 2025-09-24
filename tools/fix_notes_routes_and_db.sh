#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"

ROUTES="backend/routes.py"
RUNPY="run.py"
LOG=".tmp/paste12.log"
DB="${PASTE12_DB:-app.db}"

[ -f "$ROUTES" ] || { echo "[!] No encuentro $ROUTES"; exit 1; }

echo "[+] Backup de routes.py"
cp "$ROUTES" "$ROUTES.bak.$(date +%s)"

python - "$ROUTES" <<'PY'
import re, sys
p=sys.argv[1]
s=open(p,'r',encoding='utf-8').read()

# 0) Detectar nombre del blueprint (bp por defecto)
m_bp = re.search(r'(?m)^\s*([A-Za-z_]\w*)\s*=\s*Blueprint\(\s*[\'"]api[\'"]\s*,', s)
bp = m_bp.group(1) if m_bp else "bp"

def norm_deco_for(func_name:str, rule:str, method:str, endpoint:str):
    return f"@{bp}.route('{rule}', methods=['{method}'], endpoint='{endpoint}')\n"

# 1) Normalizar bloque de decoradores de list_notes y create_note
def replace_decorators(target_func, rule, method, endpoint):
    global s
    m = re.search(r'(?m)^([ \t]*)def\s+'+re.escape(target_func)+r'\s*\(', s)
    if not m:
        return
    indent = m.group(1)
    start_def = m.start()
    # buscar inicio del bloque de decoradores pegado arriba
    i = s.rfind('\n',0,start_def) + 1
    deco_start = i
    while True:
        prev_nl = s.rfind('\n',0,deco_start-1)
        line = s[prev_nl+1:deco_start-1]
        if line.strip().startswith('@'):
            deco_start = prev_nl+1
            continue
        break
    # reemplazar todo ese bloque por UN único decorador canónico
    s = s[:deco_start] + norm_deco_for(target_func, rule, method, endpoint) + s[deco_start:]

replace_decorators('list_notes','/api/notes','GET','list_notes')
replace_decorators('create_note','/api/notes','POST','create_note')

# 2) Eliminar cualquier decorador que ate /api/notes a funciones que NO sean list_notes/create_note
def purge_wrong_notes_routes():
    global s
    lines = s.splitlines(True)
    out = []
    i=0
    while i<len(lines):
        ln = lines[i]
        m = re.match(r'^\s*@([A-Za-z_]\w*)\.route\((.*)\)\s*$', ln.strip())
        if m:
            # capturar bloque de decoradores continuos
            blok_idx = []
            j=i
            while j<len(lines) and lines[j].lstrip().startswith('@'):
                blok_idx.append(j); j+=1
            # la def siguiente:
            func_line = lines[j] if j<len(lines) else ''
            mdef = re.match(r'^\s*def\s+([A-Za-z_]\w*)\s*\(', func_line)
            fname = mdef.group(1) if mdef else None

            keep = [k for k in blok_idx]  # por defecto conservamos todos
            for k in blok_idx:
                text = lines[k]
                if "/api/notes" in text.replace('"',"'"):
                    # sólo mantener si apunta a list_notes/create_note
                    if fname not in ("list_notes","create_note"):
                        # descartar ESTE decorador
                        keep.remove(k)
            # escribir sólo los que queden
            for k in blok_idx:
                if k in keep:
                    out.append(lines[k])
                else:
                    out.append("# FIX-REMOVED wrong /api/notes mapping\n")
            # continuar con la def y resto
            if j<len(lines):
                out.append(lines[j]); i=j+1
            else:
                i=j
            continue
        out.append(ln); i+=1
    s=''.join(out)

purge_wrong_notes_routes()

# 3) Comentar cualquier add_url_rule(... '/api/notes' ...) que no apunte a create_note/list_notes
def find_paren_close(text, start_paren):
    depth=0
    i=start_paren
    while i<len(text):
        if text[i]=='(':
            depth+=1
        elif text[i]==')':
            depth-=1
            if depth==0:
                return i
        i+=1
    return None

i=0
while True:
    m = re.search(r'(?ms)\b'+re.escape(bp)+r'\.add_url_rule\s*\(', s[i:])
    if not m: break
    start = i + m.start()
    paren = s.find('(', start)
    end = find_paren_close(s, paren) or (paren+1)
    call = s[start:end+1]
    if "/api/notes" in call.replace('"',"'"):
        # ¿apunta a view_func deseado?
        ok = re.search(r"view_func\s*=\s*(create_note|list_notes)\b", call) is not None
        if not ok:
            s = s[:start] + "# FIX-REMOVED wrong add_url_rule for /api/notes\n" + s[end+1:]
            i = start + 1
            continue
    i = end + 1

# 4) Compactar líneas en blanco
s = re.sub(r'\n{3,}','\n\n',s)

open(p,'w',encoding='utf-8').write(s)
print("[OK] routes.py: /api/notes → GET:list_notes, POST:create_note; removidos mapeos incorrectos.")
PY

# 5) Migración SQLite local (author_fp)
if command -v sqlite3 >/dev/null 2>&1 && [ -f "$DB" ]; then
  echo "[+] Verificando/migrando DB local ($DB)"
  if ! sqlite3 "$DB" 'PRAGMA table_info(note);' | awk -F'|' '{print $2}' | grep -q '^author_fp$'; then
    sqlite3 "$DB" 'ALTER TABLE note ADD COLUMN author_fp TEXT NOT NULL DEFAULT "noctx";'
  fi
  sqlite3 "$DB" 'CREATE INDEX IF NOT EXISTS idx_note_author_fp ON note(author_fp);'
else
  echo "[i] Sin sqlite3 o sin DB local ($DB); omito migración."
fi

# 6) Reinicio y smoke + url_map
pkill -f "python .*run.py" 2>/dev/null || true
: > "$LOG" || true
nohup python "$RUNPY" >"$LOG" 2>&1 &
sleep 2

echo "[+] Tail log:"
tail -n 120 "$LOG" || true

PORT="$(grep -Eo '127\.0\.0\.1:[0-9]+' "$LOG" 2>/dev/null | tail -n1 | cut -d: -f2 || echo 8000)"
echo "[i] PORT_LOCAL=$PORT"

echo "[+] URL MAP runtime:"
python - <<'PY'
import importlib
try:
    app=getattr(importlib.import_module("run"),"app",None)
    rules=[(str(r),sorted([m for m in r.methods if m not in("HEAD","OPTIONS")]),r.endpoint) for r in app.url_map.iter_rules()]
    for rule,methods,ep in sorted(rules): print(f"{rule:35s}  {','.join(methods):10s}  {ep}")
    has_get=any(r for r in rules if r[0]=="/api/notes" and "GET" in r[1])
    has_post=any(r for r in rules if r[0]=="/api/notes" and "POST" in r[1])
    print(f"\n/api/notes GET:{has_get} POST:{has_post}")
except Exception as e:
    print("URLMAP ERROR",e)
PY

echo "[+] GET /api/notes (local)"
curl -i -s "http://127.0.0.1:$PORT/api/notes?page=1" | sed -n '1,60p'
echo
echo "[+] POST /api/notes (local)"
curl -i -s -X POST -H "Content-Type: application/json" -d '{"text":"after-fix","hours":24}' "http://127.0.0.1:$PORT/api/notes" | sed -n '1,100p'
echo
